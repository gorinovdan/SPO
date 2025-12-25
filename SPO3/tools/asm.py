#!/usr/bin/env python3
import argparse
import json
import struct
import sys

CONST_KIND_INT = 0
CONST_KIND_BOOL = 1
CONST_KIND_CHAR = 2
CONST_KIND_STRING = 3


def load_spec(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    by_mnemonic = {}
    by_opcode = {}
    for ins in spec.get("instructions", []):
        by_mnemonic[ins["mnemonic"].upper()] = ins
        by_opcode[ins["opcode"]] = ins
    return spec, by_mnemonic, by_opcode


def strip_comment(line):
    for token in (";", "//"):
        idx = line.find(token)
        if idx >= 0:
            line = line[:idx]
    return line.strip()


def unescape_string(s):
    if len(s) < 2 or s[0] != '"' or s[-1] != '"':
        raise ValueError("invalid string literal")
    body = s[1:-1]
    return bytes(body, "utf-8").decode("unicode_escape")


def parse_char_literal(s):
    s = s.strip()
    if len(s) < 2 or s[0] != "'" or s[-1] != "'":
        raise ValueError("invalid char literal")
    body = s[1:-1]
    if body.startswith("\\"):
        esc = body[1:]
        if esc == "n":
            return ord("\n")
        if esc == "t":
            return ord("\t")
        if esc == "\\":
            return ord("\\")
        if esc == "'":
            return ord("'")
        if esc == '"':
            return ord('"')
        raise ValueError("unsupported char escape")
    if len(body) != 1:
        raise ValueError("invalid char literal")
    return ord(body)


def int_to_bytes(value, size):
    if size == 1:
        return struct.pack("<b", int(value))
    if size == 2:
        return struct.pack("<h", int(value))
    if size == 4:
        return struct.pack("<i", int(value))
    raise ValueError("unsupported size")

def parse_data_directive(directive, arg, path, line_no):
    token = directive.upper()
    if token.startswith("."):
        token = token[1:]

    if token in ("STRING", "DB") and arg.startswith("\""):
        return {"kind": "string", "value": unescape_string(arg), "size": None, "line": line_no}
    if token in ("CHAR", "DB") and arg.startswith("'"):
        return {"kind": "char", "value": parse_char_literal(arg), "size": 1, "line": line_no}
    if token in ("BYTE", "DB"):
        value = int(arg, 0) if arg else 0
        return {"kind": "byte", "value": value, "size": 1, "line": line_no}
    if token in ("INT", "WORD", "DD"):
        value = int(arg, 0) if arg else 0
        return {"kind": "int", "value": value, "size": 4, "line": line_no}
    if token in ("SPACE", "RESB"):
        size = int(arg, 0) if arg else 0
        if size < 0:
            raise ValueError(f"{path}:{line_no}: invalid space size")
        return {"kind": "space", "value": size, "size": size, "line": line_no}
    raise ValueError(f"{path}:{line_no}: unsupported directive {directive}")


def build_const_section(defs, path):
    consts = []
    const_labels = {}
    for d in defs:
        label = d["label"]
        if label in const_labels:
            raise ValueError(f"{path}:{d['line']}: duplicate const label {label}")
        kind = d["kind"]
        const_labels[label] = len(consts)
        if kind == "string":
            consts.append({"kind": CONST_KIND_STRING, "value": d["value"]})
        elif kind == "char":
            consts.append({"kind": CONST_KIND_CHAR, "value": d["value"]})
        elif kind in ("byte", "int"):
            size = d.get("size", 4)
            consts.append({"kind": CONST_KIND_INT, "value": d["value"], "size": size})
        elif kind == "space":
            raise ValueError(f"{path}:{d['line']}: RESB not supported in const section")
        else:
            raise ValueError(f"{path}:{d['line']}: unsupported const kind {kind}")
    return consts, const_labels


def build_data_section(defs, path):
    data_labels = {}
    data_items = []
    data_bytes = bytearray()
    for d in defs:
        label = d["label"]
        if label in data_labels:
            raise ValueError(f"{path}:{d['line']}: duplicate data label {label}")
        kind = d["kind"]
        if kind == "string":
            raw = d["value"].encode("utf-8")
            addr = len(data_bytes)
            data_bytes.extend(raw)
            data_labels[label] = addr
            data_items.append({"name": label, "addr": addr, "size": len(raw)})
        elif kind == "char":
            addr = len(data_bytes)
            data_bytes.extend(int_to_bytes(d["value"], 1))
            data_labels[label] = addr
            data_items.append({"name": label, "addr": addr, "size": 1})
        elif kind == "byte":
            addr = len(data_bytes)
            data_bytes.extend(int_to_bytes(d["value"], 1))
            data_labels[label] = addr
            data_items.append({"name": label, "addr": addr, "size": 1})
        elif kind == "int":
            addr = len(data_bytes)
            data_bytes.extend(int_to_bytes(d["value"], 4))
            data_labels[label] = addr
            data_items.append({"name": label, "addr": addr, "size": 4})
        elif kind == "space":
            size = d["value"]
            addr = len(data_bytes)
            data_bytes.extend(b"\x00" * size)
            data_labels[label] = addr
            data_items.append({"name": label, "addr": addr, "size": size})
        else:
            raise ValueError(f"{path}:{d['line']}: unsupported data kind {kind}")
    return data_items, data_labels, data_bytes


def parse_asm(path):
    section = None
    has_sections = False
    const_defs = []
    data_defs = []
    flat_defs = []
    code_labels = {}
    code = []

    with open(path, "r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, 1):
            line = strip_comment(raw)
            if not line:
                continue
            if line.startswith(".const"):
                section = "const"
                has_sections = True
                continue
            if line.startswith(".data"):
                section = "data"
                has_sections = True
                continue
            if line.startswith(".code"):
                section = "code"
                has_sections = True
                continue

            if section in ("const", "data") or not has_sections:
                if ":" in line:
                    label, rest = line.split(":", 1)
                    label = label.strip()
                    rest = rest.strip()
                    if rest:
                        parts = rest.split(None, 1)
                        directive = parts[0]
                        arg = parts[1].strip() if len(parts) > 1 else ""
                        try:
                            entry = parse_data_directive(directive, arg, path, line_no)
                        except ValueError:
                            if section in ("const", "data"):
                                raise
                            entry = None
                        if entry:
                            entry["label"] = label
                            if section == "const":
                                const_defs.append(entry)
                            elif section == "data":
                                data_defs.append(entry)
                            else:
                                flat_defs.append(entry)
                            continue
                    if not has_sections:
                        if label in code_labels:
                            raise ValueError(f"{path}:{line_no}: duplicate code label {label}")
                        code_labels[label] = len(code)
                        continue
                    raise ValueError(f"{path}:{line_no}: missing directive")

            if section == "code" or not has_sections:
                if line.endswith(":"):
                    label = line[:-1].strip()
                    if label in code_labels:
                        raise ValueError(f"{path}:{line_no}: duplicate code label {label}")
                    code_labels[label] = len(code)
                    continue
                parts = line.split(None, 1)
                mnemonic = parts[0].upper()
                operands = []
                if len(parts) > 1:
                    operands = [op.strip() for op in parts[1].split(",") if op.strip()]
                code.append({"mnemonic": mnemonic, "operands": operands, "line": line_no})
                continue

            raise ValueError(f"{path}:{line_no}: content outside sections")

    return has_sections, const_defs, data_defs, flat_defs, code_labels, code


def assemble(spec_path, asm_path, out_path):
    _, by_mnemonic, _ = load_spec(spec_path)
    has_sections, const_defs, data_defs, flat_defs, code_labels, code = parse_asm(asm_path)

    if has_sections:
        consts, const_labels = build_const_section(const_defs, asm_path)
        data_items, data_labels, data_bytes = build_data_section(data_defs, asm_path)
    else:
        const_refs = set()
        data_refs = set()
        for inst in code:
            spec = by_mnemonic.get(inst["mnemonic"])
            if not spec:
                raise ValueError(f"{asm_path}:{inst['line']}: unknown instruction {inst['mnemonic']}")
            opspec = spec.get("operands", [])
            if len(inst["operands"]) != len(opspec):
                raise ValueError(f"{asm_path}:{inst['line']}: operand count mismatch for {inst['mnemonic']}")
            for op_text, op_type in zip(inst["operands"], opspec):
                if op_type == "const":
                    const_refs.add(op_text)
                elif op_type == "data":
                    data_refs.add(op_text)

        const_defs = []
        data_defs = []
        for d in flat_defs:
            label = d["label"]
            if label in const_refs and label in data_refs:
                raise ValueError(f"{asm_path}:{d['line']}: label used as both const and data: {label}")
            if label in const_refs:
                const_defs.append(d)
            else:
                data_defs.append(d)

        consts, const_labels = build_const_section(const_defs, asm_path)
        data_items, data_labels, data_bytes = build_data_section(data_defs, asm_path)

    imports = []
    import_index = {}
    encoded_code = []

    for inst in code:
        if inst["mnemonic"] not in by_mnemonic:
            raise ValueError(f"{asm_path}:{inst['line']}: unknown instruction {inst['mnemonic']}")
        spec = by_mnemonic[inst["mnemonic"]]
        opspec = spec.get("operands", [])
        if len(inst["operands"]) != len(opspec):
            raise ValueError(f"{asm_path}:{inst['line']}: operand count mismatch for {inst['mnemonic']}")

        encoded_ops = []
        for op_text, op_type in zip(inst["operands"], opspec):
            if op_type == "imm":
                encoded_ops.append(int(op_text, 0))
            elif op_type == "const":
                if op_text not in const_labels:
                    raise ValueError(f"{asm_path}:{inst['line']}: unknown const {op_text}")
                encoded_ops.append(const_labels[op_text])
            elif op_type == "data":
                if op_text not in data_labels:
                    raise ValueError(f"{asm_path}:{inst['line']}: unknown data {op_text}")
                encoded_ops.append(data_labels[op_text])
            elif op_type == "code":
                if op_text not in code_labels:
                    raise ValueError(f"{asm_path}:{inst['line']}: unknown label {op_text}")
                encoded_ops.append(code_labels[op_text])
            elif op_type == "code_or_builtin":
                if op_text in code_labels:
                    encoded_ops.append(code_labels[op_text])
                else:
                    if op_text not in import_index:
                        import_index[op_text] = len(imports)
                        imports.append(op_text)
                    encoded_ops.append(-(import_index[op_text] + 1))
            else:
                raise ValueError(f"{asm_path}:{inst['line']}: unsupported operand type {op_type}")

        encoded_code.append({"opcode": spec["opcode"], "operands": encoded_ops})

    entry_ip = code_labels.get("main", 0)

    with open(out_path, "wb") as f:
        f.write(b"SPO3")
        f.write(struct.pack("<B", 1))
        f.write(struct.pack("<B", 4))
        f.write(struct.pack("<H", 0))
        f.write(struct.pack("<I", len(consts)))
        f.write(struct.pack("<I", len(data_bytes)))
        f.write(struct.pack("<I", len(encoded_code)))
        f.write(struct.pack("<I", entry_ip))
        f.write(struct.pack("<I", len(imports)))
        f.write(struct.pack("<I", len(data_items)))

        for c in consts:
            kind = c.get("kind", CONST_KIND_INT)
            if kind == CONST_KIND_STRING:
                encoded = c["value"].encode("utf-8")
                f.write(struct.pack("<B", kind))
                f.write(struct.pack("<I", len(encoded)))
                f.write(encoded)
            elif kind == CONST_KIND_CHAR:
                f.write(struct.pack("<B", kind))
                f.write(struct.pack("<I", 1))
                f.write(int_to_bytes(c["value"], 1))
            elif kind in (CONST_KIND_INT, CONST_KIND_BOOL):
                size = c.get("size", 4)
                f.write(struct.pack("<B", CONST_KIND_INT))
                f.write(struct.pack("<I", size))
                f.write(int_to_bytes(c["value"], size))
            else:
                raise ValueError("unsupported const kind")

        for item in data_items:
            f.write(struct.pack("<I", item["addr"]))
            f.write(struct.pack("<I", item["size"]))

        f.write(data_bytes)

        for name in imports:
            enc = name.encode("utf-8")
            f.write(struct.pack("<I", len(enc)))
            f.write(enc)

        for inst in encoded_code:
            f.write(struct.pack("<B", inst["opcode"]))
            for op in inst["operands"]:
                f.write(struct.pack("<i", int(op)))


def main():
    parser = argparse.ArgumentParser(description="Assemble SPO3 VM listing")
    parser.add_argument("-s", "--spec", required=True, help="Path to VM spec.json")
    parser.add_argument("-i", "--input", required=True, help="Input .asm file")
    parser.add_argument("-o", "--output", required=True, help="Output .bin file")
    args = parser.parse_args()

    try:
        assemble(args.spec, args.input, args.output)
    except Exception as exc:
        print(f"asm error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
