# ex:ts=4:sw=4:sts=4:et
# -*- tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*-
"""
BitBake 'Data' implementations

Functions for interacting with the data structure used by the
BitBake build tools.

The expandData and update_data are the most expensive
operations. At night the cookie monster came by and
suggested 'give me cookies on setting the variables and
things will work out'. Taking this suggestion into account
applying the skills from the not yet passed 'Entwurf und
Analyse von Algorithmen' lecture and the cookie
monster seems to be right. We will track setVar more carefully
to have faster update_data and expandKeys operations.

This is a treade-off between speed and memory again but
the speed is more critical here.
"""

# Copyright (C) 2003, 2004  Chris Larson
# Copyright (C) 2005        Holger Hans Peter Freyther
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
#
#Based on functions from the base bb module, Copyright 2003 Holger Schurig

import sys, os, re
if sys.argv[0][-5:] == "pydoc":
    path = os.path.dirname(os.path.dirname(sys.argv[1]))
else:
    path = os.path.dirname(os.path.dirname(sys.argv[0]))
sys.path.insert(0, path)
from itertools import groupby

from bb import data_smart
from bb import codeparser
import bb

logger = data_smart.logger
_dict_type = data_smart.DataSmart

def init():
    """Return a new object representing the Bitbake data"""
    return _dict_type()

def init_db(parent = None):
    """Return a new object representing the Bitbake data,
    optionally based on an existing object"""
    if parent:
        return parent.createCopy()
    else:
        return _dict_type()

def createCopy(source):
    """Link the source set to the destination
    If one does not find the value in the destination set,
    search will go on to the source set to get the value.
    Value from source are copy-on-write. i.e. any try to
    modify one of them will end up putting the modified value
    in the destination set.
    """
    return source.createCopy()

def initVar(var, d):
    """Non-destructive var init for data structure"""
    d.initVar(var)


def setVar(var, value, d):
    """Set a variable to a given value"""
    d.setVar(var, value)


def getVar(var, d, exp = 0):
    """Gets the value of a variable"""
    return d.getVar(var, exp)


def renameVar(key, newkey, d):
    """Renames a variable from key to newkey"""
    d.renameVar(key, newkey)

def delVar(var, d):
    """Removes a variable from the data set"""
    d.delVar(var)

def setVarFlag(var, flag, flagvalue, d):
    """Set a flag for a given variable to a given value"""
    d.setVarFlag(var, flag, flagvalue)

def getVarFlag(var, flag, d):
    """Gets given flag from given var"""
    return d.getVarFlag(var, flag)

def delVarFlag(var, flag, d):
    """Removes a given flag from the variable's flags"""
    d.delVarFlag(var, flag)

def setVarFlags(var, flags, d):
    """Set the flags for a given variable

    Note:
        setVarFlags will not clear previous
        flags. Think of this method as
        addVarFlags
    """
    d.setVarFlags(var, flags)

def getVarFlags(var, d):
    """Gets a variable's flags"""
    return d.getVarFlags(var)

def delVarFlags(var, d):
    """Removes a variable's flags"""
    d.delVarFlags(var)

def keys(d):
    """Return a list of keys in d"""
    return d.keys()


__expand_var_regexp__ = re.compile(r"\${[^{}]+}")
__expand_python_regexp__ = re.compile(r"\${@.+?}")

def expand(s, d, varname = None):
    """Variable expansion using the data store"""
    return d.expand(s, varname)

def expandKeys(alterdata, readdata = None):
    if readdata == None:
        readdata = alterdata

    todolist = {}
    for key in keys(alterdata):
        if not '${' in key:
            continue

        ekey = expand(key, readdata)
        if key == ekey:
            continue
        todolist[key] = ekey

    # These two for loops are split for performance to maximise the
    # usefulness of the expand cache

    for key in todolist:
        ekey = todolist[key]
        renameVar(key, ekey, alterdata)

def inheritFromOS(d, savedenv, permitted):
    """Inherit variables from the initial environment."""
    exportlist = bb.utils.preserved_envvars_exported()
    for s in savedenv.keys():
        if s in permitted:
            try:
                setVar(s, getVar(s, savedenv, True), d)
                if s in exportlist:
                    setVarFlag(s, "export", True, d)
            except TypeError:
                pass

def emit_var(var, o=sys.__stdout__, d = init(), all=False):
    """Emit a variable to be sourced by a shell."""
    if getVarFlag(var, "python", d):
        return 0

    export = getVarFlag(var, "export", d)
    unexport = getVarFlag(var, "unexport", d)
    func = getVarFlag(var, "func", d)
    if not all and not export and not unexport and not func:
        return 0

    try:
        if all:
            oval = getVar(var, d, 0)
        val = getVar(var, d, 1)
    except (KeyboardInterrupt, bb.build.FuncFailed):
        raise
    except Exception as exc:
        o.write('# expansion of %s threw %s: %s\n' % (var, exc.__class__.__name__, str(exc)))
        return 0

    if all:
        commentVal = re.sub('\n', '\n#', str(oval))
        o.write('# %s=%s\n' % (var, commentVal))

    if (var.find("-") != -1 or var.find(".") != -1 or var.find('{') != -1 or var.find('}') != -1 or var.find('+') != -1) and not all:
        return 0

    varExpanded = expand(var, d)

    if unexport:
        o.write('unset %s\n' % varExpanded)
        return 0

    if not val:
        return 0

    val = str(val)

    if func:
        # NOTE: should probably check for unbalanced {} within the var
        o.write("%s() {\n%s\n}\n" % (varExpanded, val))
        return 1

    if export:
        o.write('export ')

    # if we're going to output this within doublequotes,
    # to a shell, we need to escape the quotes in the var
    alter = re.sub('"', '\\"', val.strip())
    alter = re.sub('\n', ' \\\n', alter)
    o.write('%s="%s"\n' % (varExpanded, alter))
    return 0

def emit_env(o=sys.__stdout__, d = init(), all=False):
    """Emits all items in the data store in a format such that it can be sourced by a shell."""

    isfunc = lambda key: bool(d.getVarFlag(key, "func"))
    keys = sorted((key for key in d.keys() if not key.startswith("__")), key=isfunc)
    grouped = groupby(keys, isfunc)
    for isfunc, keys in grouped:
        for key in keys:
            emit_var(key, o, d, all and not isfunc) and o.write('\n')

def exported_keys(d):
    return (key for key in d.keys() if not key.startswith('__') and
                                      d.getVarFlag(key, 'export') and
                                      not d.getVarFlag(key, 'unexport'))

def exported_vars(d):
    for key in exported_keys(d):
        try:
            value = d.getVar(key, True)
        except Exception:
            pass

        if value is not None:
            yield key, str(value)

def emit_func(func, o=sys.__stdout__, d = init()):
    """Emits all items in the data store in a format such that it can be sourced by a shell."""

    keys = (key for key in d.keys() if not key.startswith("__") and not d.getVarFlag(key, "func"))
    for key in keys:
        emit_var(key, o, d, False) and o.write('\n')

    emit_var(func, o, d, False) and o.write('\n')
    newdeps = bb.codeparser.ShellParser(func, logger).parse_shell(d.getVar(func, True))
    seen = set()
    while newdeps:
        deps = newdeps
        seen |= deps
        newdeps = set()
        for dep in deps:
            if d.getVarFlag(dep, "func"):
               emit_var(dep, o, d, False) and o.write('\n')
               newdeps |=  bb.codeparser.ShellParser(dep, logger).parse_shell(d.getVar(dep, True))
        newdeps -= seen

def update_data(d):
    """Performs final steps upon the datastore, including application of overrides"""
    d.finalize()

def build_dependencies(key, keys, shelldeps, vardepvals, d):
    deps = set()
    vardeps = d.getVarFlag(key, "vardeps", True)
    try:
        value = d.getVar(key, False)
        if key in vardepvals:
           value =  d.getVarFlag(key, "vardepvalue", True)
        elif d.getVarFlag(key, "func"):
            if d.getVarFlag(key, "python"):
                parsedvar = d.expandWithRefs(value, key)
                parser = bb.codeparser.PythonParser(key, logger)
                parser.parse_python(parsedvar.value)
                deps = deps | parser.references
            else:
                parsedvar = d.expandWithRefs(value, key)
                parser = bb.codeparser.ShellParser(key, logger)
                parser.parse_shell(parsedvar.value)
                deps = deps | shelldeps
            if vardeps is None:
                parser.log.flush()
            deps = deps | parsedvar.references
            deps = deps | (keys & parser.execs) | (keys & parsedvar.execs)
        else:
            parser = d.expandWithRefs(value, key)
            deps |= parser.references
            deps = deps | (keys & parser.execs)
        deps |= set((vardeps or "").split())
        deps -= set((d.getVarFlag(key, "vardepsexclude", True) or "").split())
    except:
        bb.note("Error expanding variable %s" % key)
        raise
    return deps, value
    #bb.note("Variable %s references %s and calls %s" % (key, str(deps), str(execs)))
    #d.setVarFlag(key, "vardeps", deps)

def generate_dependencies(d):

    keys = set(key for key in d.keys() if not key.startswith("__"))
    shelldeps = set(key for key in keys if d.getVarFlag(key, "export") and not d.getVarFlag(key, "unexport"))
    vardepvals = set(key for key in keys if d.getVarFlag(key, "vardepvalue"))

    deps = {}
    values = {}

    tasklist = d.getVar('__BBTASKS') or []
    for task in tasklist:
        deps[task], values[task] = build_dependencies(task, keys, shelldeps, vardepvals, d)
        newdeps = deps[task]
        seen = set()
        while newdeps:
            nextdeps = newdeps
            seen |= nextdeps
            newdeps = set()
            for dep in nextdeps:
                if dep not in deps:
                    deps[dep], values[dep] = build_dependencies(dep, keys, shelldeps, vardepvals, d)
                newdeps |=  deps[dep]
            newdeps -= seen
        #print "For %s: %s" % (task, str(taskdeps[task]))
    return tasklist, deps, values

def inherits_class(klass, d):
    val = getVar('__inherit_cache', d) or []
    if os.path.join('classes', '%s.bbclass' % klass) in val:
        return True
    return False
