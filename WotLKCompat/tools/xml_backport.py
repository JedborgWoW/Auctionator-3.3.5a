#!/usr/bin/env python3
"""
Transform modern WoW XML features (unsupported by stock 3.3.5a) into the
3.3.5a-supported form, in place.

  * mixin="A B C"            -> inject  Mixin(self, A, B, C)  at the start of the
                               element's OnLoad (creating one if needed).
  * <OnX method="Y"/>        -> <OnX>self:Y(<handler args>)</OnX>
  * <EventFrame>/<DropdownButton> -> <Frame>/<Button>

A small nesting-aware tokenizer is used (not naive regex) so that comments,
CDATA, multi-line tags, self-closing mixin frames and <Scripts>-without-OnLoad
are all handled correctly. function= handlers and everything else are left
untouched, so diffs stay minimal.
"""
import re, sys, os

# Script-handler argument lists (besides the implicit self) for method= -> inline.
SCRIPT_ARGS = {
    "OnLoad": "", "OnShow": "", "OnHide": "", "OnTextSet": "",
    "OnEnterPressed": "", "OnEscapePressed": "", "OnEditFocusGained": "",
    "OnEditFocusLost": "", "OnTabPressed": "", "OnSpacePressed": "",
    "OnDragStop": "", "OnReceiveDrag": "",
    "OnEnter": "motion", "OnLeave": "motion",
    "OnMouseDown": "button", "OnMouseUp": "button", "OnDoubleClick": "button",
    "OnDragStart": "button",
    "OnClick": "button, down", "PostClick": "button, down",
    "OnUpdate": "elapsed",
    "OnEvent": "event, ...",
    "OnKeyDown": "key", "OnKeyUp": "key",
    "OnChar": "text",
    "OnTextChanged": "userInput, ...",
    "OnValueChanged": "value, ...",
    "OnSizeChanged": "width, height",
    "OnMouseWheel": "delta",
    "OnVerticalScroll": "offset", "OnHorizontalScroll": "offset",
    "OnScrollRangeChanged": "xrange, yrange",
    "OnHyperlinkEnter": "link, text", "OnHyperlinkLeave": "link, text",
    "OnHyperlinkClick": "link, text, button",
    "OnAttributeChanged": "name, value",
}

RENAME = {"EventFrame": "Frame", "DropdownButton": "Button"}

TOKEN_RE = re.compile(r"<!--.*?-->|<!\[CDATA\[.*?\]\]>|<[^>]*>", re.DOTALL)
TAG_RE = re.compile(r"^<(/?)\s*([A-Za-z0-9_]+)(.*?)(/?)>$", re.DOTALL)
MIXIN_RE = re.compile(r'\s*mixin="([^"]*)"')
METHOD_RE = re.compile(r'\bmethod="([A-Za-z0-9_]+)"')

stats = {"mixin_onload": 0, "mixin_scripts": 0, "mixin_elem": 0,
         "mixin_selfclose": 0, "method": 0, "rename": 0}


def mixin_call(value):
    parts = value.split()
    return "Mixin(self, " + ", ".join(parts) + ")"


def method_body(name, method):
    args = SCRIPT_ARGS.get(name, "...")  # unknown handler: forward everything
    return "self:%s(%s)" % (method, args)


def transform(text):
    out = []
    stack = []  # list of dicts: {name, mixin, injected}
    pos = 0
    for m in TOKEN_RE.finditer(text):
        # raw text between tokens
        if m.start() > pos:
            out.append(text[pos:m.start()])
        pos = m.end()
        tok = m.group(0)

        # comments / CDATA: emit unchanged
        if tok.startswith("<!--") or tok.startswith("<!["):
            out.append(tok)
            continue

        tm = TAG_RE.match(tok)
        if not tm:
            out.append(tok)
            continue
        closing, name, attrs, selfclose = tm.group(1), tm.group(2), tm.group(3), tm.group(4)
        is_close = closing == "/"
        is_self = selfclose == "/"

        # --- closing tag ---
        if is_close:
            out_name = RENAME.get(name, name)
            if name in RENAME:
                stats["rename"] += 1
            if name == "Scripts":
                # inject into the Scripts of the parent mixin element if needed
                parent = stack[-2] if len(stack) >= 2 else None
                if parent and parent["mixin"] and not parent["injected"]:
                    out.append("<OnLoad>%s</OnLoad>" % mixin_call(parent["mixin"]))
                    parent["injected"] = True
                    stats["mixin_scripts"] += 1
                out.append("</%s>" % out_name)
                if stack:
                    stack.pop()
                continue
            # element close
            elem = stack[-1] if stack else None
            if elem and elem["mixin"] and not elem["injected"]:
                out.append("<Scripts><OnLoad>%s</OnLoad></Scripts>" % mixin_call(elem["mixin"]))
                elem["injected"] = True
                stats["mixin_elem"] += 1
            out.append("</%s>" % out_name)
            if stack:
                stack.pop()
            continue

        # --- self-closing tag ---
        if is_self:
            # script handler with method=
            if name.startswith("On"):
                mm = METHOD_RE.search(attrs)
                if mm:
                    method = mm.group(1)
                    body = method_body(name, method)
                    stats["method"] += 1
                    # OnLoad on a mixin element: prepend the Mixin call
                    if name == "OnLoad":
                        parent = stack[-2] if len(stack) >= 2 else None
                        if parent and parent["mixin"] and not parent["injected"]:
                            body = "%s; %s" % (mixin_call(parent["mixin"]), body)
                            parent["injected"] = True
                            stats["mixin_onload"] += 1
                    out.append("<%s>%s</%s>" % (name, body, name))
                    continue
                # function= or other: leave untouched
                out.append(tok)
                continue
            # self-closing element possibly carrying a mixin
            mx = MIXIN_RE.search(attrs)
            if mx:
                value = mx.group(1)
                attrs2 = MIXIN_RE.sub("", attrs, count=1)
                out_name = RENAME.get(name, name)
                if name in RENAME:
                    stats["rename"] += 1
                out.append("<%s%s>" % (out_name, attrs2))
                out.append("<Scripts><OnLoad>%s</OnLoad></Scripts>" % mixin_call(value))
                out.append("</%s>" % out_name)
                stats["mixin_selfclose"] += 1
                continue
            # plain self-closing element (maybe rename)
            out_name = RENAME.get(name, name)
            if name in RENAME:
                stats["rename"] += 1
                out.append("<%s%s/>" % (out_name, attrs))
            else:
                out.append(tok)
            continue

        # --- opening tag ---
        # inline OnLoad: inject Mixin at start of body
        if name == "OnLoad":
            out.append("<OnLoad>")
            parent = stack[-2] if len(stack) >= 2 else None
            if parent and parent["mixin"] and not parent["injected"]:
                out.append("%s; " % mixin_call(parent["mixin"]))
                parent["injected"] = True
                stats["mixin_onload"] += 1
            stack.append({"name": "OnLoad", "mixin": None, "injected": False})
            continue

        mx = MIXIN_RE.search(attrs)
        mixin_value = mx.group(1) if mx else None
        if mx:
            attrs = MIXIN_RE.sub("", attrs, count=1)
        out_name = RENAME.get(name, name)
        if name in RENAME:
            stats["rename"] += 1
        out.append("<%s%s>" % (out_name, attrs))
        stack.append({"name": out_name, "mixin": mixin_value, "injected": False})

    if pos < len(text):
        out.append(text[pos:])
    return "".join(out)


def main(roots):
    files = []
    for root in roots:
        for dirpath, _, names in os.walk(root):
            for n in names:
                if n.endswith(".xml"):
                    files.append(os.path.join(dirpath, n))
    changed = 0
    for path in sorted(files):
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
        dst = transform(src)
        if dst != src:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(dst)
            changed += 1
    print("files scanned:", len(files), "changed:", changed)
    print("stats:", stats)


if __name__ == "__main__":
    main(sys.argv[1:])
