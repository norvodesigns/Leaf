#!/usr/bin/env python3
"""Structural checker for Leaf.xcodeproj/project.pbxproj (stdlib only).

The project file is edited by hand and the machines that edit it (Linux boxes, CI log readers) cannot run Xcode, so a
slip only shows up as a failed 15 minute CI round. This script finds the slips that can be found without Xcode:

  * syntax: balanced braces and parentheses, terminated strings, a readable property list
  * ids: 24 uppercase hex digits, defined exactly once, every reference resolves, nothing left unreferenced
  * targets: build phases, configuration lists, products, dependencies, synchronized folders that exist
  * embedding: embed phases hold real products, the producing target is a dependency, bundle ids nest, versions agree
  * files: Info.plist and entitlements inside a synchronized folder are excluded so they are not bundled as resources
  * Leaf's own contract: bundle ids, entitlements, Info.plist keys, which targets compile which folders

Usage:
    python3 scripts/check_pbxproj.py             # check this repo; exit status 1 when anything is wrong
    python3 scripts/check_pbxproj.py --summary   # also print the targets and what they embed
    python3 scripts/check_pbxproj.py --self-test # break the project in memory and prove each break is caught
"""

import argparse
import os
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ID_LIKE = re.compile(r"^[0-9A-Fa-f]{24}$")
ID_OK = re.compile(r"^[0-9A-F]{24}$")

# ---------------------------------------------------------------------------------------------------------------------
# Leaf's own contract. Everything above the "Leaf expectations" check is generic; the values here are what this app ships.
# ---------------------------------------------------------------------------------------------------------------------

APP = "Leaf"
TESTS = "LeafTests"
WATCH = "LeafWatch"
WIDGETS = "LeafWidgets"
BUNDLE_IDS = {
    APP: "com.norvodesigns.leaf",
    TESTS: "com.norvodesigns.leafTests",
    WATCH: "com.norvodesigns.leaf.watchkitapp",
    WIDGETS: "com.norvodesigns.leaf.widgets",
}
APP_GROUP = "group.com.norvodesigns.leaf"
ICLOUD_CONTAINER = "iCloud.com.norvodesigns.leaf"
WIDGET_EXTENSION_POINT = "com.apple.widgetkit-extension"
# Folder -> the exact set of targets that compile it.
FOLDER_MEMBERS = {
    "Shared": {APP, WATCH},
    "Leaf": {APP},
    "LeafWatch": {WATCH},
    "LeafTests": {TESTS},
    "LeafWidgets": {WIDGETS},
    "LiveActivityShared": {APP, WIDGETS},
}

PRODUCT_EXT = {
    "com.apple.product-type.application": ".app",
    "com.apple.product-type.app-extension": ".appex",
    "com.apple.product-type.bundle.unit-test": ".xctest",
}
EXT_FILE_TYPE = {".app": "wrapper.application", ".appex": "wrapper.app-extension", ".xctest": "wrapper.cfbundle"}
# dstSubfolderSpec values Xcode writes for the destinations this project uses.
DST_PLUGINS = "13"
DST_PRODUCTS = "16"
KNOWN_DST = {"0", "1", "6", "7", "8", "9", "10", "11", "12", "13", "15", "16"}
PHASE_ISAS = {
    "PBXSourcesBuildPhase",
    "PBXFrameworksBuildPhase",
    "PBXResourcesBuildPhase",
    "PBXCopyFilesBuildPhase",
    "PBXShellScriptBuildPhase",
    "PBXHeadersBuildPhase",
}


# ---------------------------------------------------------------------------------------------------------------------
# Parser for the old-style (OpenStep) property list that Xcode writes.
# ---------------------------------------------------------------------------------------------------------------------


class ParseError(Exception):
    def __init__(self, message, line):
        super().__init__(f"line {line}: {message}")
        self.line = line


class Parser:
    """Parses the project file and records where ids are defined and referenced."""

    BARE = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$/.-:@+*")

    def __init__(self, text):
        self.t = text
        self.i = 0
        self.line = 1
        self.path = []
        self.defs = {}  # id -> [line, ...] for keys of the top-level `objects` dictionary
        self.refs = []  # (id, line) for every id-shaped string used as a value or as a TargetAttributes key
        self.bad_keys = []  # (key, line) for object keys that are not valid ids
        self.dup_keys = []  # (path, key, line) for repeated dictionary keys

    # -- low level ------------------------------------------------------------------------------------------------
    def peek(self, n=1):
        return self.t[self.i : self.i + n]

    def advance(self, n=1):
        chunk = self.t[self.i : self.i + n]
        self.line += chunk.count("\n")
        self.i += n

    def skip(self):
        while self.i < len(self.t):
            c = self.t[self.i]
            if c in " \t\r\n":
                self.advance()
            elif self.peek(2) == "/*":
                end = self.t.find("*/", self.i + 2)
                if end < 0:
                    raise ParseError("unterminated /* comment", self.line)
                self.advance(end + 2 - self.i)
            elif self.peek(2) == "//":
                end = self.t.find("\n", self.i)
                self.advance((len(self.t) if end < 0 else end) - self.i)
            else:
                return

    def expect(self, ch):
        self.skip()
        if self.peek() != ch:
            found = self.peek() or "end of file"
            raise ParseError(f"expected '{ch}' but found '{found}'", self.line)
        self.advance()

    # -- values ---------------------------------------------------------------------------------------------------
    def string(self):
        self.skip()
        start_line = self.line
        if self.peek() == '"':
            j = self.i + 1
            out = []
            while True:
                if j >= len(self.t):
                    raise ParseError("unterminated string", start_line)
                ch = self.t[j]
                if ch == "\\" and j + 1 < len(self.t):
                    nxt = self.t[j + 1]
                    out.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
                    j += 2
                    continue
                if ch == '"':
                    break
                out.append(ch)
                j += 1
            self.advance(j + 1 - self.i)
            return "".join(out)
        j = self.i
        while j < len(self.t) and self.t[j] in self.BARE and self.t[j : j + 2] not in ("/*", "//"):
            j += 1
        if j == self.i:
            found = self.peek() or "end of file"
            raise ParseError(f"unexpected '{found}'", self.line)
        word = self.t[self.i : j]
        self.advance(j - self.i)
        return word

    def value(self):
        self.skip()
        c = self.peek()
        if c == "{":
            return self.dictionary()
        if c == "(":
            return self.array()
        line = self.line
        s = self.string()
        if ID_LIKE.match(s):
            self.refs.append((s, line))
        return s

    def dictionary(self):
        open_line = self.line
        self.expect("{")
        result = {}
        while True:
            self.skip()
            if self.peek() == "}":
                self.advance()
                return result
            if self.i >= len(self.t):
                raise ParseError(f"'{{' opened on line {open_line} is never closed", self.line)
            line = self.line
            key = self.string()
            self.expect("=")
            if key in result:
                self.dup_keys.append((".".join(self.path) or "<root>", key, line))
            if self.path == ["objects"]:
                self.defs.setdefault(key, []).append(line)
                if not ID_OK.match(key):
                    self.bad_keys.append((key, line))
            if self.path and self.path[-1] == "TargetAttributes" and ID_LIKE.match(key):
                self.refs.append((key, line))
            self.path.append(key)
            result[key] = self.value()
            self.path.pop()
            self.expect(";")

    def array(self):
        open_line = self.line
        self.expect("(")
        result = []
        while True:
            self.skip()
            if self.peek() == ")":
                self.advance()
                return result
            if self.i >= len(self.t):
                raise ParseError(f"'(' opened on line {open_line} is never closed", self.line)
            result.append(self.value())
            self.skip()
            if self.peek() == ",":
                self.advance()
            elif self.peek() != ")":
                raise ParseError(f"expected ',' or ')' but found '{self.peek() or 'end of file'}'", self.line)

    def parse(self):
        if not self.t.startswith("// !$*UTF8*$!"):
            raise ParseError("missing the '// !$*UTF8*$!' header", 1)
        root = self.dictionary()
        self.skip()
        if self.i < len(self.t):
            raise ParseError("unexpected text after the closing brace", self.line)
        return root


# ---------------------------------------------------------------------------------------------------------------------
# The checker.
# ---------------------------------------------------------------------------------------------------------------------


def as_list(value):
    return value if isinstance(value, list) else []


def as_dict(value):
    return value if isinstance(value, dict) else {}


class Checker:
    def __init__(self, text, root, project_rel="Leaf.xcodeproj/project.pbxproj"):
        self.text = text
        self.root = root
        self.project_rel = project_rel
        self.errors = []
        self.warnings = []
        self.objects = {}
        self.parser = None
        self.doc = {}

    # -- reporting ------------------------------------------------------------------------------------------------
    def error(self, message, oid=None):
        self.errors.append(self._where(oid) + message)

    def warn(self, message, oid=None):
        self.warnings.append(self._where(oid) + message)

    def _where(self, oid):
        if oid and self.parser and oid in self.parser.defs:
            return f"line {self.parser.defs[oid][0]}: "
        return ""

    def isa(self, oid):
        return as_dict(self.objects.get(oid)).get("isa")

    def label(self, oid):
        obj = as_dict(self.objects.get(oid))
        name = obj.get("name") or obj.get("path") or ""
        return f"{oid} ({obj.get('isa', '?')} {name})".replace(" )", ")")

    def of_isa(self, *isas):
        return [oid for oid, obj in self.objects.items() if as_dict(obj).get("isa") in isas]

    def need(self, oid, key, kind=None):
        """Returns obj[key], reporting an error when the key is missing."""
        obj = as_dict(self.objects.get(oid))
        if key not in obj:
            self.error(f"{self.label(oid)} is missing '{key}'", oid)
            return None
        value = obj[key]
        if kind is not None and not isinstance(value, kind):
            self.error(f"{self.label(oid)}: '{key}' has the wrong shape", oid)
            return None
        return value

    def target_to_id(self, oid, key, isa, owner=None):
        """Resolves obj[key] to an id of the expected isa, reporting problems."""
        owner = owner or oid
        value = as_dict(self.objects.get(oid)).get(key)
        if not isinstance(value, str):
            self.error(f"{self.label(oid)} is missing '{key}'", owner)
            return None
        if value not in self.objects:
            return None  # the dangling reference is reported once, globally
        if self.isa(value) != isa:
            self.error(f"{self.label(oid)}: '{key}' points at {self.label(value)}, expected a {isa}", owner)
            return None
        return value

    def folder_path(self, group_id):
        return os.path.join(self.root, as_dict(self.objects.get(group_id)).get("path", ""))

    # -- run ------------------------------------------------------------------------------------------------------
    def run(self):
        self.parser = Parser(self.text)
        try:
            self.doc = self.parser.parse()
        except ParseError as exc:
            self.errors.append(f"syntax error, {exc}")
            return self
        self.objects = as_dict(self.doc.get("objects"))
        if not self.objects:
            self.errors.append("the project has no 'objects' dictionary")
            return self
        self.check_ids()
        self.check_sections()
        self.check_project()
        self.check_targets()
        self.check_configuration_lists()
        self.check_phases()
        self.check_dependencies()
        self.check_groups()
        self.check_synchronized_groups()
        self.check_embedding()
        self.check_files_on_disk()
        self.check_schemes()
        self.check_leaf_expectations()
        return self

    # -- ids ------------------------------------------------------------------------------------------------------
    def check_ids(self):
        p = self.parser
        for path, key, line in p.dup_keys:
            self.errors.append(f"line {line}: duplicate key '{key}' inside {path}")
        for key, line in p.bad_keys:
            self.errors.append(f"line {line}: object key '{key}' is not 24 uppercase hex digits")
        for oid, lines in sorted(p.defs.items()):
            if len(lines) > 1:
                where = ", ".join(str(n) for n in lines)
                self.errors.append(f"id {oid} is defined more than once (lines {where})")
        referenced = set()
        for ref, line in p.refs:
            if not ID_OK.match(ref):
                self.errors.append(f"line {line}: id '{ref}' must use uppercase hex digits")
                continue
            referenced.add(ref)
            if ref not in self.objects:
                self.errors.append(f"line {line}: id {ref} is referenced but never defined")
        root_object = self.doc.get("rootObject")
        if root_object not in self.objects:
            self.errors.append("rootObject does not point at a defined object")
        elif self.isa(root_object) != "PBXProject":
            self.errors.append("rootObject must be the PBXProject")
        for oid in sorted(self.objects):
            if oid not in referenced and oid != root_object:
                self.error(f"{self.label(oid)} is defined but never referenced", oid)
        if self.doc.get("objectVersion") != "77" or as_dict(self.objects.get(root_object)).get("preferredProjectObjectVersion") != "77":
            self.warn("objectVersion / preferredProjectObjectVersion are not 77 (the synchronized folder format)")

    def check_sections(self):
        """Keeps the file in the shape Xcode writes (sorted sections, objects in the section for their isa)."""
        begin = re.compile(r"^/\* Begin (\w+) section \*/$")
        end = re.compile(r"^/\* End (\w+) section \*/$")
        obj_line = re.compile(r"^\t\t([0-9A-F]{24}) ")
        current, order, last_id = None, [], ""
        for number, line in enumerate(self.text.split("\n"), 1):
            m = begin.match(line)
            if m:
                if current:
                    self.warn(f"line {number}: section {current} is not closed before {m.group(1)} begins")
                current, last_id = m.group(1), ""
                order.append(current)
                continue
            m = end.match(line)
            if m:
                if m.group(1) != current:
                    self.warn(f"line {number}: 'End {m.group(1)} section' does not match the open section {current}")
                current = None
                continue
            m = obj_line.match(line)
            if m and current:
                oid = m.group(1)
                if self.isa(oid) and self.isa(oid) != current:
                    self.warn(f"line {number}: {oid} is a {self.isa(oid)} but sits in the {current} section")
                if oid < last_id:
                    self.warn(f"line {number}: {oid} is out of order in the {current} section")
                last_id = oid
            elif m and not current:
                self.warn(f"line {number}: object {m.group(1)} sits outside any section")
        if current:
            self.warn(f"section {current} is never closed")
        if order != sorted(order):
            self.warn("sections are not in alphabetical order, which is how Xcode writes them")

    # -- project, targets, configurations ---------------------------------------------------------------------------
    def project_id(self):
        return self.doc.get("rootObject")

    def targets(self):
        return [oid for oid in self.of_isa("PBXNativeTarget")]

    def target_name(self, tid):
        return as_dict(self.objects.get(tid)).get("name")

    def check_project(self):
        pid = self.project_id()
        if self.isa(pid) != "PBXProject":
            return
        for key in ("mainGroup", "productRefGroup"):
            self.target_to_id(pid, key, "PBXGroup")
        self.target_to_id(pid, "buildConfigurationList", "XCConfigurationList")
        listed = as_list(self.need(pid, "targets", list))
        native = self.targets()
        for tid in listed:
            if tid in self.objects and self.isa(tid) != "PBXNativeTarget":
                self.error(f"project target {self.label(tid)} is not a PBXNativeTarget", pid)
        if sorted(listed) != sorted(native):
            missing = sorted(set(native) - set(listed))
            extra = sorted(set(listed) - set(native))
            self.error(f"the project's targets list disagrees with the targets defined (not listed: {missing}, unknown: {extra})", pid)
        if len(set(listed)) != len(listed):
            self.error("a target is listed twice in the project's targets", pid)
        attributes = as_dict(as_dict(self.objects[pid].get("attributes")).get("TargetAttributes"))
        for key, value in attributes.items():
            if key not in native:
                self.error(f"TargetAttributes has an entry for {key}, which is not a target", pid)
            test_target = as_dict(value).get("TestTargetID")
            if test_target and test_target not in native:
                self.error(f"TestTargetID {test_target} is not a target", pid)
        for tid in native:
            if tid not in attributes:
                self.warn(f"{self.label(tid)} has no TargetAttributes entry (Xcode adds CreatedOnToolsVersion)", pid)
        names = [self.target_name(t) for t in native]
        for name in set(names):
            if names.count(name) > 1:
                self.error(f"two targets are named '{name}'", pid)

    def product_name(self, tid, config):
        raw = self.effective(tid, config, "PRODUCT_NAME")
        if raw is None:
            return None
        if raw == "$(TARGET_NAME)":
            return self.target_name(tid)
        return None if "$(" in raw else raw

    def check_targets(self):
        seen_phases = {}
        products_group = as_dict(self.objects.get(as_dict(self.objects.get(self.project_id())).get("productRefGroup")))
        product_children = as_list(products_group.get("children"))
        for tid in self.targets():
            name = self.target_name(tid)
            for key in ("name", "productName", "productType"):
                self.need(tid, key, str)
            self.need(tid, "buildRules", list)
            self.need(tid, "dependencies", list)
            self.target_to_id(tid, "buildConfigurationList", "XCConfigurationList")
            phases = as_list(self.need(tid, "buildPhases", list))
            if not phases:
                self.error(f"target {name} has no build phases", tid)
            for phase in phases:
                if phase not in self.objects:
                    continue
                if self.isa(phase) not in PHASE_ISAS:
                    self.error(f"target {name}: {self.label(phase)} is not a build phase", tid)
                if phase in seen_phases:
                    self.error(f"build phase {phase} belongs to both {seen_phases[phase]} and {name}", tid)
                seen_phases[phase] = name
            kinds = [self.isa(ph) for ph in phases]
            for needed in ("PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"):
                if needed not in kinds:
                    self.error(f"target {name} has no {needed}", tid)
            product_type = as_dict(self.objects[tid]).get("productType")
            ref = self.target_to_id(tid, "productReference", "PBXFileReference")
            if product_type not in PRODUCT_EXT:
                self.warn(f"target {name} has a product type this checker does not know: {product_type}", tid)
            elif ref:
                expected = PRODUCT_EXT[product_type]
                file_ref = self.objects[ref]
                configs = self.configs_of(tid)
                for config in configs:
                    base = self.product_name(tid, config)
                    if base and file_ref.get("path") != base + expected:
                        self.error(f"target {name}: product file is '{file_ref.get('path')}' but {config} builds '{base + expected}'", tid)
                if file_ref.get("explicitFileType") != EXT_FILE_TYPE[expected]:
                    self.error(f"target {name}: product {file_ref.get('path')} should have explicitFileType {EXT_FILE_TYPE[expected]}", tid)
                if file_ref.get("sourceTree") != "BUILT_PRODUCTS_DIR":
                    self.error(f"target {name}: product {file_ref.get('path')} must live in BUILT_PRODUCTS_DIR", tid)
                if ref not in product_children:
                    self.error(f"target {name}: product {file_ref.get('path')} is not in the Products group", tid)
            for dep in as_list(self.objects[tid].get("dependencies")):
                if dep in self.objects and self.isa(dep) != "PBXTargetDependency":
                    self.error(f"target {name}: dependency {self.label(dep)} is not a PBXTargetDependency", tid)
            groups = as_list(self.objects[tid].get("fileSystemSynchronizedGroups"))
            if len(set(groups)) != len(groups):
                self.error(f"target {name} lists a synchronized folder twice", tid)
            for g in groups:
                if g in self.objects and self.isa(g) != "PBXFileSystemSynchronizedRootGroup":
                    self.error(f"target {name}: {self.label(g)} is not a synchronized root group", tid)

    def configs_of(self, owner_id):
        """Maps configuration name -> buildSettings for the owner's (target or project) configuration list."""
        lst = as_dict(self.objects.get(as_dict(self.objects.get(owner_id)).get("buildConfigurationList")))
        out = {}
        for cid in as_list(lst.get("buildConfigurations")):
            cfg = as_dict(self.objects.get(cid))
            if isinstance(cfg.get("name"), str):
                out[cfg["name"]] = as_dict(cfg.get("buildSettings"))
        return out

    def effective(self, tid, config, key):
        target = self.configs_of(tid).get(config, {})
        if key in target:
            return target[key] if isinstance(target[key], str) else None
        project = self.configs_of(self.project_id()).get(config, {})
        value = project.get(key)
        return value if isinstance(value, str) else None

    def check_configuration_lists(self):
        in_lists = {}
        project_names = None
        for lid in self.of_isa("XCConfigurationList"):
            configs = as_list(self.need(lid, "buildConfigurations", list))
            if not configs:
                self.error(f"{self.label(lid)} has no build configurations", lid)
            names = []
            for cid in configs:
                if cid not in self.objects:
                    continue
                if self.isa(cid) != "XCBuildConfiguration":
                    self.error(f"{self.label(lid)} holds {self.label(cid)}, which is not an XCBuildConfiguration", lid)
                    continue
                names.append(self.objects[cid].get("name"))
                if cid in in_lists:
                    self.error(f"{self.label(cid)} is in two configuration lists", lid)
                in_lists[cid] = lid
            if len(set(names)) != len(names):
                self.error(f"{self.label(lid)} repeats a configuration name", lid)
            default = as_dict(self.objects[lid]).get("defaultConfigurationName")
            if default not in names:
                self.error(f"{self.label(lid)}: defaultConfigurationName '{default}' is not one of {names}", lid)
            if project_names is None:
                project_names = sorted(n for n in names if n)
            elif sorted(n for n in names if n) != project_names:
                self.error(f"{self.label(lid)} has configurations {names}, other lists have {project_names}", lid)
        for cid in self.of_isa("XCBuildConfiguration"):
            self.need(cid, "name", str)
            self.need(cid, "buildSettings", dict)

    # -- build phases ---------------------------------------------------------------------------------------------
    def check_phases(self):
        in_phase = {}
        for pid in self.of_isa(*PHASE_ISAS):
            obj = self.objects[pid]
            self.need(pid, "buildActionMask", str)
            for bid in as_list(self.need(pid, "files", list)):
                if bid not in self.objects:
                    continue
                if self.isa(bid) != "PBXBuildFile":
                    self.error(f"{self.label(pid)} holds {self.label(bid)}, which is not a PBXBuildFile", pid)
                if bid in in_phase:
                    self.error(f"{self.label(bid)} is in two build phases", pid)
                in_phase[bid] = pid
            if obj.get("isa") == "PBXCopyFilesBuildPhase":
                spec = self.need(pid, "dstSubfolderSpec", str)
                if spec is not None and spec not in KNOWN_DST:
                    self.error(f"{self.label(pid)}: dstSubfolderSpec {spec} is not a destination Xcode writes", pid)
                if "dstPath" not in obj:
                    self.error(f"{self.label(pid)} is missing 'dstPath' (use \"\" for none)", pid)
        for bid in self.of_isa("PBXBuildFile"):
            if "fileRef" not in self.objects[bid] and "productRef" not in self.objects[bid]:
                self.error(f"{self.label(bid)} has neither fileRef nor productRef", bid)
            ref = self.objects[bid].get("fileRef")
            if ref in self.objects and self.isa(ref) != "PBXFileReference":
                self.error(f"{self.label(bid)}: fileRef is {self.label(ref)}, expected a PBXFileReference", bid)

    def check_dependencies(self):
        pid = self.project_id()
        for did in self.of_isa("PBXTargetDependency"):
            target = self.target_to_id(did, "target", "PBXNativeTarget")
            proxy = self.target_to_id(did, "targetProxy", "PBXContainerItemProxy")
            if target and proxy:
                p = self.objects[proxy]
                if p.get("remoteGlobalIDString") != target:
                    self.error(f"{self.label(did)}: its proxy points at {p.get('remoteGlobalIDString')}, not at {target}", did)
                if p.get("remoteInfo") != self.target_name(target):
                    self.error(f"{self.label(did)}: proxy remoteInfo '{p.get('remoteInfo')}' should be '{self.target_name(target)}'", did)
        for xid in self.of_isa("PBXContainerItemProxy"):
            p = self.objects[xid]
            if p.get("containerPortal") != pid:
                self.error(f"{self.label(xid)}: containerPortal must be the project object {pid}", xid)
            if p.get("proxyType") != "1":
                self.error(f"{self.label(xid)}: proxyType should be 1 for a target dependency", xid)
            if p.get("remoteGlobalIDString") not in self.objects:
                self.error(f"{self.label(xid)}: remoteGlobalIDString does not name a defined object", xid)
        # A dependency cycle makes Xcode refuse to build.
        graph = {}
        for tid in self.targets():
            deps = set()
            for did in as_list(self.objects[tid].get("dependencies")):
                dep = as_dict(self.objects.get(did)).get("target")
                if dep:
                    deps.add(dep)
            graph[tid] = deps

        def visit(node, stack):
            if node in stack:
                self.error("target dependency cycle: " + " -> ".join(self.target_name(n) or n for n in stack + [node]))
                return
            for nxt in graph.get(node, ()):
                visit(nxt, stack + [node])

        for tid in graph:
            visit(tid, [])

    # -- groups ---------------------------------------------------------------------------------------------------
    def check_groups(self):
        parent_of = {}
        pid = self.project_id()
        main = as_dict(self.objects.get(pid)).get("mainGroup")
        for gid in self.of_isa("PBXGroup"):
            for child in as_list(self.need(gid, "children", list)):
                if child not in self.objects:
                    continue
                if self.isa(child) not in ("PBXGroup", "PBXFileReference", "PBXFileSystemSynchronizedRootGroup", "PBXVariantGroup"):
                    self.error(f"{self.label(gid)} has child {self.label(child)}, which cannot be in a group", gid)
                if child in parent_of:
                    self.error(f"{self.label(child)} is a child of two groups", gid)
                parent_of[child] = gid
        for sid in self.of_isa("PBXFileSystemSynchronizedRootGroup"):
            if sid not in parent_of:
                self.error(f"synchronized folder {self.label(sid)} is not shown in any group", sid)
        for gid in self.of_isa("PBXGroup"):
            if gid != main and gid not in parent_of:
                self.error(f"group {self.label(gid)} is not reachable from the main group", gid)
        for fid in self.of_isa("PBXFileReference"):
            if fid not in parent_of:
                self.error(f"file {self.label(fid)} is not in any group", fid)

    def check_synchronized_groups(self):
        users = {}
        for tid in self.targets():
            for g in as_list(self.objects[tid].get("fileSystemSynchronizedGroups")):
                users.setdefault(g, []).append(tid)
        used_exceptions = {}
        for gid in self.of_isa("PBXFileSystemSynchronizedRootGroup"):
            obj = self.objects[gid]
            path = self.need(gid, "path", str)
            if gid not in users:
                self.error(f"synchronized folder {self.label(gid)} is not used by any target", gid)
            if path is not None and not os.path.isdir(self.folder_path(gid)):
                self.error(f"synchronized folder '{path}' does not exist next to the .xcodeproj", gid)
            seen_targets = set()
            for xid in as_list(obj.get("exceptions")):
                if xid not in self.objects:
                    continue
                if self.isa(xid) != "PBXFileSystemSynchronizedBuildFileExceptionSet":
                    self.error(f"{self.label(gid)}: exception {self.label(xid)} has the wrong type", gid)
                    continue
                used_exceptions.setdefault(xid, []).append(gid)
                target = self.target_to_id(xid, "target", "PBXNativeTarget")
                if target:
                    if target not in users.get(gid, []):
                        self.error(f"{self.label(xid)} excludes files for {self.target_name(target)}, which does not compile {path}", xid)
                    if target in seen_targets:
                        self.error(f"{self.label(gid)} has two exception sets for {self.target_name(target)}", gid)
                    seen_targets.add(target)
                for member in as_list(self.need(xid, "membershipExceptions", list)):
                    if not os.path.exists(os.path.join(self.folder_path(gid), member)):
                        self.error(f"{self.label(xid)}: excluded file '{member}' does not exist in {path}", xid)
        for xid in self.of_isa("PBXFileSystemSynchronizedBuildFileExceptionSet"):
            if len(used_exceptions.get(xid, [])) != 1:
                self.error(f"{self.label(xid)} must belong to exactly one synchronized folder", xid)

    def exclusions(self, tid, gid):
        out = set()
        for xid in as_list(as_dict(self.objects.get(gid)).get("exceptions")):
            x = as_dict(self.objects.get(xid))
            if x.get("target") == tid:
                out.update(as_list(x.get("membershipExceptions")))
        return out

    # -- embedding ------------------------------------------------------------------------------------------------
    def producer_of(self, file_ref):
        for tid in self.targets():
            if self.objects[tid].get("productReference") == file_ref:
                return tid
        return None

    def embedded(self, tid):
        """Yields (copy phase id, producing target id) for every product the target embeds."""
        for phase in as_list(self.objects[tid].get("buildPhases")):
            if self.isa(phase) != "PBXCopyFilesBuildPhase":
                continue
            for bid in as_list(self.objects[phase].get("files")):
                ref = as_dict(self.objects.get(bid)).get("fileRef")
                yield phase, self.producer_of(ref), bid

    def dependency_targets(self, tid):
        out = set()
        for did in as_list(self.objects[tid].get("dependencies")):
            dep = as_dict(self.objects.get(did)).get("target")
            if dep:
                out.add(dep)
        return out

    def check_embedding(self):
        for tid in self.targets():
            owner = self.target_name(tid)
            for phase, producer, bid in self.embedded(tid):
                if producer is None:
                    self.error(f"{self.label(phase)} embeds {self.label(bid)}, which is not the product of any target", phase)
                    continue
                child = self.target_name(producer)
                if producer not in self.dependency_targets(tid):
                    self.error(f"{owner} embeds {child} but {child} is not a target dependency of {owner} (a clean build would find nothing to embed)", phase)
                spec = self.objects[phase].get("dstSubfolderSpec")
                ptype = self.objects[producer].get("productType")
                if ptype == "com.apple.product-type.app-extension" and spec != DST_PLUGINS:
                    self.error(f"{owner}: app extension {child} must be embedded with dstSubfolderSpec {DST_PLUGINS} (PlugIns), not {spec}", phase)
                if ptype == "com.apple.product-type.application":
                    watchos = self.effective(producer, "Release", "SDKROOT") == "watchos"
                    if watchos and not (spec == DST_PRODUCTS and str(self.objects[phase].get("dstPath", "")).endswith("/Watch")):
                        self.error(f"{owner}: the watch app {child} must be embedded in $(CONTENTS_FOLDER_PATH)/Watch (dstSubfolderSpec {DST_PRODUCTS})", phase)
                self.check_embedded_settings(tid, producer)

    def check_embedded_settings(self, owner_id, child_id):
        owner, child = self.target_name(owner_id), self.target_name(child_id)
        for config in self.configs_of(owner_id):
            owner_bundle = self.effective(owner_id, config, "PRODUCT_BUNDLE_IDENTIFIER")
            child_bundle = self.effective(child_id, config, "PRODUCT_BUNDLE_IDENTIFIER")
            if owner_bundle and child_bundle and not child_bundle.startswith(owner_bundle + "."):
                self.error(f"{child} ({config}) bundle id '{child_bundle}' must start with {owner} bundle id '{owner_bundle}.'", child_id)
            for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
                a, b = self.effective(owner_id, config, key), self.effective(child_id, config, key)
                if a != b:
                    self.error(f"{child} ({config}) has {key} {b}, but {owner} has {a}; embedded bundles must match their host", child_id)
            companion = self.effective(child_id, config, "INFOPLIST_KEY_WKCompanionAppBundleIdentifier")
            if companion and companion != owner_bundle:
                self.error(f"{child} ({config}): WKCompanionAppBundleIdentifier is '{companion}', the host is '{owner_bundle}'", child_id)
            for key in ("IPHONEOS_DEPLOYMENT_TARGET",):
                a, b = self.effective(owner_id, config, key), self.effective(child_id, config, key)
                if a and b and tuple(map(float, b.split("."))) > tuple(map(float, a.split("."))):
                    self.error(f"{child} ({config}) needs {key} {b}, newer than {owner}'s {a}", child_id)

    # -- files on disk ----------------------------------------------------------------------------------------------
    def swift_files(self, folder):
        for base, _dirs, files in os.walk(folder):
            for name in files:
                if name.endswith(".swift"):
                    yield os.path.join(base, name)

    def check_files_on_disk(self):
        for tid in self.targets():
            name = self.target_name(tid)
            groups = [g for g in as_list(self.objects[tid].get("fileSystemSynchronizedGroups")) if g in self.objects]
            # Settings that point at files.
            for config, settings in self.configs_of(tid).items():
                for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
                    value = settings.get(key)
                    if not isinstance(value, str) or "$(" in value:
                        continue
                    full = os.path.join(self.root, value)
                    if not os.path.isfile(full):
                        self.error(f"target {name} ({config}): {key} = {value} but that file does not exist", tid)
                        continue
                    try:
                        with open(full, "rb") as handle:
                            plistlib.load(handle)
                    except Exception as exc:  # plistlib raises several unrelated types
                        self.error(f"target {name}: {value} is not a readable property list ({exc})", tid)
                    for gid in groups:
                        folder = os.path.abspath(self.folder_path(gid))
                        full_abs = os.path.abspath(full)
                        if full_abs.startswith(folder + os.sep):
                            rel = os.path.relpath(full_abs, folder)
                            if rel not in self.exclusions(tid, gid):
                                self.error(
                                    f"target {name}: {value} ({key}) sits in the synchronized folder {as_dict(self.objects[gid]).get('path')} "
                                    f"but is not a membership exception, so it would be bundled as a resource",
                                    tid,
                                )
            # Any stray plist or entitlements file in a synchronized folder.
            for gid in groups:
                folder = self.folder_path(gid)
                for base, _dirs, files in os.walk(folder):
                    for fname in files:
                        if fname == "Info.plist" or fname.endswith(".entitlements"):
                            rel = os.path.relpath(os.path.join(base, fname), folder)
                            if rel not in self.exclusions(tid, gid):
                                self.error(f"target {name}: {rel} in {as_dict(self.objects[gid]).get('path')} would be bundled as a resource; add it to the folder's membership exceptions", tid)
            # Swift refuses two files with the same name in one module, even from different folders.
            names = {}
            for gid in groups:
                for path in self.swift_files(self.folder_path(gid)):
                    names.setdefault(os.path.basename(path), []).append(os.path.relpath(path, self.root))
            for base, paths in sorted(names.items()):
                if len(paths) > 1:
                    self.error(f"target {name} compiles '{base}' more than once: {', '.join(sorted(paths))} (Swift: filename used twice)", tid)

    def check_schemes(self):
        folder = os.path.join(self.root, os.path.dirname(self.project_rel), "xcshareddata", "xcschemes")
        if not os.path.isdir(folder):
            return
        for fname in sorted(os.listdir(folder)):
            if not fname.endswith(".xcscheme"):
                continue
            try:
                tree = ET.parse(os.path.join(folder, fname))
            except ET.ParseError as exc:
                self.error(f"scheme {fname} is not valid XML ({exc})")
                continue
            for ref in tree.iter("BuildableReference"):
                tid = ref.get("BlueprintIdentifier")
                if tid not in self.objects or self.isa(tid) != "PBXNativeTarget":
                    self.error(f"scheme {fname} points at {tid}, which is not a target")
                    continue
                target = self.objects[tid]
                product = as_dict(self.objects.get(target.get("productReference"))).get("path")
                if ref.get("BlueprintName") != target.get("name"):
                    self.error(f"scheme {fname}: BlueprintName '{ref.get('BlueprintName')}' should be '{target.get('name')}'")
                if ref.get("BuildableName") != product:
                    self.error(f"scheme {fname}: BuildableName '{ref.get('BuildableName')}' should be '{product}'")

    # -- Leaf expectations ------------------------------------------------------------------------------------------
    def load_plist(self, rel):
        try:
            with open(os.path.join(self.root, rel), "rb") as handle:
                return plistlib.load(handle)
        except Exception:
            return None

    def by_name(self):
        return {self.target_name(t): t for t in self.targets()}

    def check_leaf_expectations(self):
        named = self.by_name()
        for name in BUNDLE_IDS:
            if name not in named:
                self.error(f"expected a target named {name}")
        if any(name not in named for name in BUNDLE_IDS):
            return
        for name, bundle in BUNDLE_IDS.items():
            for config in self.configs_of(named[name]):
                actual = self.effective(named[name], config, "PRODUCT_BUNDLE_IDENTIFIER")
                if actual != bundle:
                    self.error(f"{name} ({config}) bundle id is '{actual}', expected '{bundle}'", named[name])
                if self.effective(named[name], config, "SWIFT_VERSION") != "5.0":
                    self.error(f"{name} ({config}) must build in Swift 5 language mode (SWIFT_VERSION = 5.0)", named[name])
                key = "WATCHOS_DEPLOYMENT_TARGET" if name == WATCH else "IPHONEOS_DEPLOYMENT_TARGET"
                if self.effective(named[name], config, key) != "26.0":
                    self.error(f"{name} ({config}) {key} should be 26.0", named[name])
        teams = {
            self.effective(named[n], c, "DEVELOPMENT_TEAM") for n in BUNDLE_IDS for c in self.configs_of(named[n])
        }
        if len(teams) > 1:
            self.error(f"targets disagree about DEVELOPMENT_TEAM: {sorted(str(t) for t in teams)}")
        widgets = named[WIDGETS]
        if self.objects[widgets].get("productType") != "com.apple.product-type.app-extension":
            self.error("LeafWidgets must be an app extension", widgets)
        if widgets not in {p for _ph, p, _b in self.embedded(named[APP])}:
            self.error("Leaf must embed LeafWidgets.appex (Embed Foundation Extensions)", named[APP])
        if named[WATCH] not in {p for _ph, p, _b in self.embedded(named[APP])}:
            self.error("Leaf must embed LeafWatch.app", named[APP])
        for gid in self.of_isa("PBXFileSystemSynchronizedRootGroup"):
            folder = as_dict(self.objects[gid]).get("path")
            members = {self.target_name(t) for t in self.targets() if gid in as_list(self.objects[t].get("fileSystemSynchronizedGroups"))}
            if folder in FOLDER_MEMBERS and members != FOLDER_MEMBERS[folder]:
                self.error(f"folder {folder} is compiled by {sorted(members)}, expected {sorted(FOLDER_MEMBERS[folder])}", gid)
        for folder in FOLDER_MEMBERS:
            if not any(as_dict(self.objects[g]).get("path") == folder for g in self.of_isa("PBXFileSystemSynchronizedRootGroup")):
                self.error(f"expected a synchronized folder named {folder}")
        self.check_leaf_plists()
        self.check_widget_sources()

    def check_leaf_plists(self):
        app_info = self.load_plist("Config/Info.plist")
        if app_info is None:
            self.error("Config/Info.plist is missing or unreadable")
        else:
            if app_info.get("NSSupportsLiveActivities") is not True:
                self.error("Config/Info.plist: NSSupportsLiveActivities must be true")
            if app_info.get("NSSupportsLiveActivitiesFrequentUpdates") is not False:
                self.error("Config/Info.plist: NSSupportsLiveActivitiesFrequentUpdates must be false")
            if "remote-notification" not in as_list(app_info.get("UIBackgroundModes")):
                self.error("Config/Info.plist: UIBackgroundModes must include remote-notification (CloudKit silent pushes)")
            if app_info.get("ITSAppUsesNonExemptEncryption") is not False:
                self.error("Config/Info.plist: ITSAppUsesNonExemptEncryption must stay false")
        widget_info = self.load_plist("Config/LeafWidgets-Info.plist")
        if widget_info is None:
            self.error("Config/LeafWidgets-Info.plist is missing or unreadable")
        elif as_dict(widget_info.get("NSExtension")).get("NSExtensionPointIdentifier") != WIDGET_EXTENSION_POINT:
            self.error(f"Config/LeafWidgets-Info.plist: NSExtension.NSExtensionPointIdentifier must be {WIDGET_EXTENSION_POINT}")
        app_ent = self.load_plist("Leaf/Leaf.entitlements")
        widget_ent = self.load_plist("LeafWidgets/LeafWidgets.entitlements")
        if app_ent is None:
            self.error("Leaf/Leaf.entitlements is missing or unreadable")
        else:
            if ICLOUD_CONTAINER not in as_list(app_ent.get("com.apple.developer.icloud-container-identifiers")):
                self.error(f"Leaf.entitlements: icloud-container-identifiers must include {ICLOUD_CONTAINER}")
            if "CloudKit" not in as_list(app_ent.get("com.apple.developer.icloud-services")):
                self.error("Leaf.entitlements: icloud-services must include CloudKit")
            if APP_GROUP not in as_list(app_ent.get("com.apple.security.application-groups")):
                self.error(f"Leaf.entitlements: application-groups must include {APP_GROUP}")
            if app_ent.get("aps-environment") not in ("development", "production"):
                self.error("Leaf.entitlements: aps-environment must be development or production")
        if widget_ent is None:
            self.error("LeafWidgets/LeafWidgets.entitlements is missing or unreadable")
        elif as_list(widget_ent.get("com.apple.security.application-groups")) != [APP_GROUP]:
            self.error(f"LeafWidgets.entitlements: application-groups must be exactly [{APP_GROUP}]")
        named = self.by_name()
        for name, rel in ((APP, "Leaf/Leaf.entitlements"), (WIDGETS, "LeafWidgets/LeafWidgets.entitlements")):
            for config in self.configs_of(named[name]):
                if self.effective(named[name], config, "CODE_SIGN_ENTITLEMENTS") != rel:
                    self.error(f"{name} ({config}) must set CODE_SIGN_ENTITLEMENTS = {rel}", named[name])
        for name, rel in ((APP, "Config/Info.plist"), (WIDGETS, "Config/LeafWidgets-Info.plist")):
            for config in self.configs_of(named[name]):
                if self.effective(named[name], config, "INFOPLIST_FILE") != rel:
                    self.error(f"{name} ({config}) must set INFOPLIST_FILE = {rel}", named[name])

    def check_widget_sources(self):
        """The extension needs exactly one @main (the bundle) or it will not link."""
        count = 0
        for folder in ("LeafWidgets", "LiveActivityShared"):
            for path in self.swift_files(os.path.join(self.root, folder)):
                with open(path, encoding="utf-8") as handle:
                    count += len(re.findall(r"^\s*@main\b", handle.read(), re.M))
        if count != 1:
            self.error(f"the LeafWidgets extension must contain exactly one @main, found {count}")

    # -- output -----------------------------------------------------------------------------------------------------
    def summary(self):
        lines = []
        for tid in sorted(self.targets(), key=lambda t: self.target_name(t)):
            name = self.target_name(tid)
            product = as_dict(self.objects.get(self.objects[tid].get("productReference"))).get("path")
            bundle = self.effective(tid, "Release", "PRODUCT_BUNDLE_IDENTIFIER")
            groups = [as_dict(self.objects[g]).get("path") for g in as_list(self.objects[tid].get("fileSystemSynchronizedGroups")) if g in self.objects]
            embeds = [self.target_name(p) for _ph, p, _b in self.embedded(tid) if p]
            deps = sorted(self.target_name(t) for t in self.dependency_targets(tid) if t in self.objects)
            lines.append(f"{name}: {product}  {bundle}")
            lines.append(f"    folders: {', '.join(groups)}")
            lines.append(f"    depends on: {', '.join(deps) or '-'}   embeds: {', '.join(embeds) or '-'}")
        return "\n".join(lines)


# ---------------------------------------------------------------------------------------------------------------------
# Self-test: break the project in memory in ways Xcode would reject, and prove the checker notices each one.
# ---------------------------------------------------------------------------------------------------------------------

W = "4C1EAF00000000000000"  # prefix of the ids added for the widget extension


def mutations():
    def replace(old, new, count=1):
        def apply(text):
            if text.count(old) != count:
                raise AssertionError(f"self-test mutation expected {count} match(es) of {old!r}, found {text.count(old)}")
            return text.replace(old, new)

        return apply

    def drop_line(fragment):
        def apply(text):
            lines = text.split("\n")
            hits = [i for i, line in enumerate(lines) if fragment in line]
            if len(hits) != 1:
                raise AssertionError(f"self-test mutation expected one line containing {fragment!r}, found {len(hits)}")
            del lines[hits[0]]
            return "\n".join(lines)

        return apply

    return [
        ("unclosed brace", lambda t: t.rstrip().rsplit("}", 1)[0] + "\n", "syntax error"),
        ("unclosed parenthesis", replace(f"{W}01A5 /* LeafWidgets.appex */,\n\t\t\t);", f"{W}01A5 /* LeafWidgets.appex */,\n\t\t\t}};"), "syntax error"),
        ("unterminated string", replace('name = "Embed Foundation Extensions";', 'name = "Embed Foundation Extensions;'), "syntax error"),
        ("duplicate id", replace(f"\t\t{W}01C3 /* Resources */ = {{", f"\t\t{W}01C2 /* Resources */ = {{"), "defined more than once"),
        ("missing definition", drop_line(f"{W}01C5 /* LeafWidgets.appex in Embed Foundation Extensions */ = {{isa"), "referenced but never defined"),
        ("lowercase id", replace(f"remoteGlobalIDString = {W}01B1;", f"remoteGlobalIDString = {W.lower()}01b1;"), "uppercase"),
        ("unreferenced object", replace("/* End PBXSourcesBuildPhase section */", f"\t\t{W}0999 /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n/* End PBXSourcesBuildPhase section */"), "never referenced"),
        ("synchronized folder missing", replace("path = LiveActivityShared;", "path = LiveActivitySharedX;"), "does not exist"),
        ("embed without dependency", drop_line(f"{W}01D2 /* PBXTargetDependency */,"), "not a target dependency"),
        ("entitlements bundled as resource", replace("\t\t\t\tLeaf.entitlements,\n", ""), "bundled as a resource"),
        ("exception for a file that is gone", replace("\t\t\t\tLeafWidgets.entitlements,\n", "\t\t\t\tGone.entitlements,\n"), "does not exist in LeafWidgets"),
        ("extension bundle id outside the app", replace("PRODUCT_BUNDLE_IDENTIFIER = com.norvodesigns.leaf.widgets;", "PRODUCT_BUNDLE_IDENTIFIER = com.norvodesigns.widgets;", 2), "must start with"),
        ("extension embedded in the wrong place", replace("dstSubfolderSpec = 13;", "dstSubfolderSpec = 7;"), "PlugIns"),
        ("target without build phases", replace(f"\t\t\t\t{W}01C1 /* Sources */,\n\t\t\t\t{W}01C2 /* Frameworks */,\n\t\t\t\t{W}01C3 /* Resources */,\n", ""), "no build phases"),
        ("target without a configuration list", drop_line(f"buildConfigurationList = {W}01E1"), "buildConfigurationList"),
        ("product file name drifts", replace("path = LeafWidgets.appex;", "path = LeafWidgetsX.appex;"), "product file is"),
        ("version mismatch with the host", replace(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = LeafWidgets/LeafWidgets.entitlements;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;", f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = LeafWidgets/LeafWidgets.entitlements;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tMARKETING_VERSION = 2.0;", 2), "must match their host"),
        ("wrong Swift language mode", replace("SWIFT_VERSION = 5.0;", "SWIFT_VERSION = 6.0;", 8), "Swift 5 language mode"),
        ("entitlements file setting removed", replace("\t\t\t\tCODE_SIGN_ENTITLEMENTS = LeafWidgets/LeafWidgets.entitlements;\n", "", 2), "CODE_SIGN_ENTITLEMENTS"),
        ("shared folder leaks into the widget", replace(f"\t\t\t\t{W}01A3 /* LeafWidgets */,\n\t\t\t\t{W}01A4 /* LiveActivityShared */,\n\t\t\t);\n\t\t\tname = LeafWidgets;", f"\t\t\t\t{W}01A3 /* LeafWidgets */,\n\t\t\t\t4C1EAF0000000000000000A8 /* Shared */,\n\t\t\t\t{W}01A4 /* LiveActivityShared */,\n\t\t\t);\n\t\t\tname = LeafWidgets;"), "expected ['Leaf', 'LeafWatch']"),
        ("proxy points at the wrong target", replace(f"remoteGlobalIDString = {W}01B1;", "remoteGlobalIDString = 4C1EAF0000000000000000B3;"), "its proxy points at"),
    ]


def self_test(root, text):
    baseline = Checker(text, root).run()
    if baseline.errors:
        print("self-test needs a clean project first; the checker reports:")
        for message in baseline.errors:
            print("  error:", message)
        return 1
    failures = 0
    for name, mutate, expected in mutations():
        try:
            broken = mutate(text)
        except AssertionError as exc:
            print(f"FAIL  {name}: {exc}")
            failures += 1
            continue
        result = Checker(broken, root).run()
        if any(expected in message for message in result.errors):
            print(f"ok    {name}")
        else:
            failures += 1
            print(f"FAIL  {name}: expected an error containing {expected!r}, got:")
            for message in result.errors[:5] or ["(no errors at all)"]:
                print("        ", message)
    total = len(mutations())
    print(f"{total - failures}/{total} broken projects were caught")
    return 1 if failures else 0


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Structural checker for Leaf.xcodeproj/project.pbxproj")
    parser.add_argument("--root", default=os.path.dirname(here), help="repository root (default: the parent of scripts/)")
    parser.add_argument("--summary", action="store_true", help="print the targets and what they embed")
    parser.add_argument("--self-test", action="store_true", help="prove the checker catches deliberately broken projects")
    args = parser.parse_args()

    rel = "Leaf.xcodeproj/project.pbxproj"
    try:
        with open(os.path.join(args.root, rel), encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print(f"error: cannot read {rel}: {exc}")
        return 1

    if args.self_test:
        return self_test(args.root, text)

    checker = Checker(text, args.root, rel).run()
    if args.summary and checker.objects:
        print(checker.summary())
    for message in checker.warnings:
        print("warning:", message)
    for message in checker.errors:
        print("error:", message)
    if checker.errors:
        print(f"{rel}: {len(checker.errors)} error(s), {len(checker.warnings)} warning(s)")
        return 1
    print(f"{rel}: OK ({len(checker.objects)} objects, {len(checker.targets())} targets, {len(checker.warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
