#!/usr/bin/env python
# ex:ts=4:sw=4:sts=4:et
# -*- tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*-
"""
   class for handling .bb files

   Reads a .bb file and obtains its metadata

"""


#  Copyright (C) 2003, 2004  Chris Larson
#  Copyright (C) 2003, 2004  Phil Blundell
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

from __future__ import absolute_import
import re, bb, os
import logging
import bb.build, bb.utils
from bb import data

from . import ConfHandler
from .. import resolve_file, ast, logger
from .ConfHandler import include, init

# For compatibility
bb.deprecate_import(__name__, "bb.parse", ["vars_from_file"])

__func_start_regexp__    = re.compile( r"(((?P<py>python)|(?P<fr>fakeroot))\s*)*(?P<func>[\w\.\-\+\{\}\$]+)?\s*\(\s*\)\s*{$" )
__inherit_regexp__       = re.compile( r"inherit\s+(.+)" )
__export_func_regexp__   = re.compile( r"EXPORT_FUNCTIONS\s+(.+)" )
__addtask_regexp__       = re.compile("addtask\s+(?P<func>\w+)\s*((before\s*(?P<before>((.*(?=after))|(.*))))|(after\s*(?P<after>((.*(?=before))|(.*)))))*")
__addhandler_regexp__    = re.compile( r"addhandler\s+(.+)" )
__def_regexp__           = re.compile( r"def\s+(\w+).*:" )
__python_func_regexp__   = re.compile( r"(\s+.*)|(^$)" )


__infunc__ = ""
__inpython__ = False
__body__   = []
__classname__ = ""
classes = [ None, ]

cached_statements = {}

# We need to indicate EOF to the feeder. This code is so messy that
# factoring it out to a close_parse_file method is out of question.
# We will use the IN_PYTHON_EOF as an indicator to just close the method
#
# The two parts using it are tightly integrated anyway
IN_PYTHON_EOF = -9999999999999



def supports(fn, d):
    """Return True if fn has a supported extension"""
    return os.path.splitext(fn)[-1] in [".bb", ".bbclass", ".inc"]

def inherit(files, d):
    __inherit_cache = data.getVar('__inherit_cache', d) or []
    fn = ""
    lineno = 0
    for file in files:
        file = data.expand(file, d)
        if not os.path.isabs(file) and not file.endswith(".bbclass"):
            file = os.path.join('classes', '%s.bbclass' % file)

        if not file in __inherit_cache:
            logger.log(logging.DEBUG -1, "BB %s:%d: inheriting %s", fn, lineno, file)
            __inherit_cache.append( file )
            data.setVar('__inherit_cache', __inherit_cache, d)
            include(fn, file, d, "inherit")
            __inherit_cache = data.getVar('__inherit_cache', d) or []

def get_statements(filename, absolute_filename, base_name):
    global cached_statements

    try:
        return cached_statements[absolute_filename]
    except KeyError:
        file = open(absolute_filename, 'r')
        statements = ast.StatementGroup()

        lineno = 0
        while True:
            lineno = lineno + 1
            s = file.readline()
            if not s: break
            s = s.rstrip()
            feeder(lineno, s, filename, base_name, statements)
        if __inpython__:
            # add a blank line to close out any python definition
            feeder(IN_PYTHON_EOF, "", filename, base_name, statements)

        if filename.endswith(".bbclass") or filename.endswith(".inc"):
            cached_statements[absolute_filename] = statements
        return statements

def handle(fn, d, include):
    global __func_start_regexp__, __inherit_regexp__, __export_func_regexp__, __addtask_regexp__, __addhandler_regexp__, __infunc__, __body__, __residue__
    __body__ = []
    __infunc__ = ""
    __classname__ = ""
    __residue__ = []


    if include == 0:
        logger.debug(2, "BB %s: handle(data)", fn)
    else:
        logger.debug(2, "BB %s: handle(data, include)", fn)

    base_name = os.path.basename(fn)
    (root, ext) = os.path.splitext(base_name)
    init(d)

    if ext == ".bbclass":
        __classname__ = root
        classes.append(__classname__)
        __inherit_cache = data.getVar('__inherit_cache', d) or []
        if not fn in __inherit_cache:
            __inherit_cache.append(fn)
            data.setVar('__inherit_cache', __inherit_cache, d)

    if include != 0:
        oldfile = data.getVar('FILE', d)
    else:
        oldfile = None

    abs_fn = resolve_file(fn, d)

    if include:
        bb.parse.mark_dependency(d, abs_fn)

    # actual loading
    statements = get_statements(fn, abs_fn, base_name)

    # DONE WITH PARSING... time to evaluate
    if ext != ".bbclass":
        data.setVar('FILE', abs_fn, d)

    statements.eval(d)

    if ext == ".bbclass":
        classes.remove(__classname__)
    else:
        if include == 0:
            return ast.multi_finalize(fn, d)

    if oldfile:
        d.setVar("FILE", oldfile)

    # we have parsed the bb class now
    if ext == ".bbclass" or ext == ".inc":
        bb.methodpool.get_parsed_dict()[base_name] = 1

    return d

def feeder(lineno, s, fn, root, statements):
    global __func_start_regexp__, __inherit_regexp__, __export_func_regexp__, __addtask_regexp__, __addhandler_regexp__, __def_regexp__, __python_func_regexp__, __inpython__, __infunc__, __body__, classes, bb, __residue__
    if __infunc__:
        if s == '}':
            __body__.append('')
            ast.handleMethod(statements, fn, lineno, __infunc__, __body__)
            __infunc__ = ""
            __body__ = []
        else:
            __body__.append(s)
        return

    if __inpython__:
        m = __python_func_regexp__.match(s)
        if m and lineno != IN_PYTHON_EOF:
            __body__.append(s)
            return
        else:
            ast.handlePythonMethod(statements, fn, lineno, __inpython__,
                                   root, __body__)
            __body__ = []
            __inpython__ = False

            if lineno == IN_PYTHON_EOF:
                return

    if s and s[0] == '#':
        if len(__residue__) != 0 and __residue__[0][0] != "#":
            bb.error("There is a comment on line %s of file %s (%s) which is in the middle of a multiline expression.\nBitbake used to ignore these but no longer does so, please fix your metadata as errors are likely as a result of this change." % (lineno, fn, s))

    if s and s[-1] == '\\':
        __residue__.append(s[:-1])
        return

    s = "".join(__residue__) + s
    __residue__ = []

    # Skip empty lines
    if s == '':
        return   

    # Skip comments
    if s[0] == '#':
        return

    m = __func_start_regexp__.match(s)
    if m:
        __infunc__ = m.group("func") or "__anonymous"
        ast.handleMethodFlags(statements, fn, lineno, __infunc__, m)
        return

    m = __def_regexp__.match(s)
    if m:
        __body__.append(s)
        __inpython__ = m.group(1)

        return

    m = __export_func_regexp__.match(s)
    if m:
        ast.handleExportFuncs(statements, fn, lineno, m, classes)
        return

    m = __addtask_regexp__.match(s)
    if m:
        ast.handleAddTask(statements, fn, lineno, m)
        return

    m = __addhandler_regexp__.match(s)
    if m:
        ast.handleBBHandlers(statements, fn, lineno, m)
        return

    m = __inherit_regexp__.match(s)
    if m:
        ast.handleInherit(statements, fn, lineno, m)
        return

    return ConfHandler.feeder(lineno, s, fn, statements)

# Add us to the handlers list
from .. import handlers
handlers.append({'supports': supports, 'handle': handle, 'init': init})
del handlers
