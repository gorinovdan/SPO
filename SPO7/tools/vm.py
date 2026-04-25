#!/usr/bin/env python3
import argparse
import base64
import json
import struct
import sys


class Address:
    def __init__(self, addr, frame_id=None):
        self.addr = int(addr)
        self.frame_id = frame_id

    def __repr__(self):
        if self.frame_id is None:
            return f"&{self.addr}"
        return f"&{self.frame_id}:{self.addr}"


class DataFrame:
    def __init__(self, mem, obj_mem=None):
        self.mem = mem
        self.obj_mem = obj_mem if obj_mem is not None else {}


class CallFrame:
    def __init__(self, return_ip, bp, frame_depth):
        self.return_ip = return_ip
        self.bp = bp
        self.frame_depth = frame_depth


def load_spec(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    by_opcode = {}
    for ins in spec.get("instructions", []):
        by_opcode[ins["opcode"]] = ins
    return spec, by_opcode


def read_u8(buf, off):
    return buf[off], off + 1


def read_u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0], off + 4


def read_i32(buf, off):
    return struct.unpack_from("<i", buf, off)[0], off + 4


def parse_binary(path, spec_by_opcode):
    with open(path, "rb") as f:
        data = f.read()
    off = 0
    if data[:4] != b"SPO3":
        raise ValueError("invalid magic")
    off = 4
    version = data[off]
    off += 1
    _word_size = data[off]
    off += 1
    off += 2  # reserved

    const_count, off = read_u32(data, off)
    data_size, off = read_u32(data, off)
    code_count, off = read_u32(data, off)
    entry_ip, off = read_u32(data, off)
    import_count, off = read_u32(data, off)
    data_item_count, off = read_u32(data, off)
    meta_size = 0
    if version >= 2:
        meta_size, off = read_u32(data, off)

    consts = []
    for _ in range(const_count):
        kind, off = read_u8(data, off)
        size, off = read_u32(data, off)
        raw = data[off:off + size]
        off += size
        if kind == 3:
            consts.append(raw.decode("utf-8"))
        elif kind == 2:
            consts.append(int.from_bytes(raw, "little", signed=True))
        else:
            consts.append(int.from_bytes(raw, "little", signed=True))

    data_items = []
    data_sizes = {}
    for _ in range(data_item_count):
        addr, off = read_u32(data, off)
        size, off = read_u32(data, off)
        data_items.append({"addr": addr, "size": size})
        data_sizes[addr] = size

    data_mem = bytearray(data[off:off + data_size])
    off += data_size
    meta_bytes = data[off:off + meta_size]
    off += meta_size

    imports = []
    for _ in range(import_count):
        name_len, off = read_u32(data, off)
        name = data[off:off + name_len].decode("utf-8")
        off += name_len
        imports.append(name)

    code = []
    for _ in range(code_count):
        opcode, off = read_u8(data, off)
        spec = spec_by_opcode.get(opcode)
        if not spec:
            raise ValueError(f"unknown opcode {opcode}")
        operands = []
        for _ in spec.get("operands", []):
            val, off = read_i32(data, off)
            operands.append(val)
        code.append((opcode, operands))

    return {
        "version": version,
        "consts": consts,
        "data_mem": data_mem,
        "data_sizes": data_sizes,
        "imports": imports,
        "code": code,
        "entry_ip": entry_ip,
        "meta_bytes": meta_bytes,
    }


def to_int(val):
    if isinstance(val, Address):
        raise ValueError("address used as integer")
    if isinstance(val, str):
        raise ValueError("string used as integer")
    return int(val)


def serialize_value(val):
    if isinstance(val, Address):
        return {"kind": "address", "addr": val.addr, "frame_id": val.frame_id}
    if isinstance(val, str):
        return {"kind": "string", "value": val}
    return {"kind": "int", "value": int(val)}


def dump_state(path, data_frames, data_sizes, meta_bytes):
    payload = {
        "frames": [],
        "data_sizes": {str(k): v for k, v in data_sizes.items()},
        "meta": meta_bytes.decode("utf-8", errors="ignore"),
    }
    for idx, frame in enumerate(data_frames):
        payload["frames"].append({
            "index": idx,
            "mem_b64": base64.b64encode(bytes(frame.mem)).decode("ascii"),
            "obj_mem": {str(addr): serialize_value(val) for addr, val in frame.obj_mem.items()},
        })
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def normalize_size(size, word_size):
    if size == 1:
        return 1
    return word_size


def read_mem_word(mem, addr):
    if addr < 0 or addr + 4 > len(mem):
        raise ValueError("memory read out of bounds")
    return struct.unpack_from("<i", mem, addr)[0]


def write_mem_word(mem, addr, value):
    if addr < 0 or addr + 4 > len(mem):
        raise ValueError("memory write out of bounds")
    struct.pack_into("<i", mem, addr, int(value))


def read_mem_sized(mem, addr, size):
    if addr < 0 or addr + size > len(mem):
        raise ValueError("memory read out of bounds")
    if size == 1:
        return struct.unpack_from("<b", mem, addr)[0]
    if size == 4:
        return struct.unpack_from("<i", mem, addr)[0]
    raise ValueError("unsupported read size")


def write_mem_sized(mem, addr, size, value):
    if addr < 0 or addr + size > len(mem):
        raise ValueError("memory write out of bounds")
    if size == 1:
        struct.pack_into("<b", mem, addr, int(value))
        return
    if size == 4:
        struct.pack_into("<i", mem, addr, int(value))
        return
    raise ValueError("unsupported write size")


def builtin_call(name, args):
    if name in ("printf", "print"):
        out = "".join(str(a) for a in args)
        if name == "print":
            out += "\n"
        sys.stdout.write(out)
        sys.stdout.flush()
        return 0
    if name == "read":
        try:
            line = sys.stdin.readline()
        except Exception:
            return 0
        if not line:
            return 0
        return int(line.strip())
    raise ValueError(f"unknown builtin: {name}")


def frame_read_sized(frame, addr, size):
    if addr in frame.obj_mem:
        return frame.obj_mem[addr]
    return read_mem_sized(frame.mem, addr, size)


def frame_write_sized(frame, addr, size, value):
    if isinstance(value, Address):
        if size != 4:
            raise ValueError("address stored into non-word slot")
        frame.obj_mem[addr] = value
        write_mem_sized(frame.mem, addr, size, 0)
        return
    if isinstance(value, str):
        if size != 4:
            raise ValueError("string stored into non-word slot")
        frame.obj_mem[addr] = value
        write_mem_sized(frame.mem, addr, size, 0)
        return
    if addr in frame.obj_mem:
        del frame.obj_mem[addr]
    write_mem_sized(frame.mem, addr, size, to_int(value))


def frame_read_word(frame, addr):
    if addr in frame.obj_mem:
        return frame.obj_mem[addr]
    return read_mem_word(frame.mem, addr)


def frame_write_word(frame, addr, value):
    if isinstance(value, Address):
        frame.obj_mem[addr] = value
        write_mem_word(frame.mem, addr, 0)
        return
    if isinstance(value, str):
        frame.obj_mem[addr] = value
        write_mem_word(frame.mem, addr, 0)
        return
    if addr in frame.obj_mem:
        del frame.obj_mem[addr]
    write_mem_word(frame.mem, addr, to_int(value))


def run_vm(binary, spec, spec_by_opcode, max_steps, dump_state_path=None):
    code = binary["code"]
    consts = binary["consts"]
    data_template = bytes(binary["data_mem"])
    data_sizes = binary["data_sizes"]
    imports = binary["imports"]
    meta_bytes = binary.get("meta_bytes", b"")
    word_size = spec.get("word_size", 4)

    ip = binary["entry_ip"]
    stack = []
    sp = 0
    bp = 0
    call_stack = []
    data_frames = [DataFrame(bytearray(data_template))]
    io_port = 0
    steps = 0

    def stack_push(val):
        nonlocal sp
        stack.append(val)
        sp += 1

    def stack_pop():
        nonlocal sp
        if sp == 0:
            raise ValueError("stack underflow")
        sp -= 1
        return stack.pop()

    def stack_truncate(new_sp):
        nonlocal sp
        if new_sp < 0 or new_sp > sp:
            raise ValueError("invalid stack pointer")
        if new_sp == sp:
            return
        del stack[new_sp:]
        sp = new_sp

    def current_frame():
        return data_frames[-1]

    def frame_for_address(addr):
        if addr.frame_id is None:
            return current_frame()
        if addr.frame_id < 0 or addr.frame_id >= len(data_frames):
            raise ValueError("address frame out of range")
        return data_frames[addr.frame_id]

    while 0 <= ip < len(code):
        steps += 1
        if steps > max_steps:
            raise RuntimeError("max steps exceeded")

        opcode, operands = code[ip]
        mnemonic = spec_by_opcode[opcode]["mnemonic"].upper()
        frame = current_frame()

        if mnemonic == "NOP":
            ip += 1
        elif mnemonic == "PUSH_CONST":
            idx = operands[0]
            stack_push(consts[idx])
            ip += 1
        elif mnemonic == "PUSH_ADDR":
            stack_push(Address(operands[0], len(data_frames) - 1))
            ip += 1
        elif mnemonic == "LOAD":
            addr = operands[0]
            size = normalize_size(data_sizes.get(addr, word_size), word_size)
            stack_push(frame_read_sized(frame, addr, size))
            ip += 1
        elif mnemonic == "STORE":
            addr = operands[0]
            size = normalize_size(data_sizes.get(addr, word_size), word_size)
            val = stack_pop()
            frame_write_sized(frame, addr, size, val)
            ip += 1
        elif mnemonic == "LOAD_IND":
            addr = stack_pop()
            if not isinstance(addr, Address):
                raise ValueError("LOAD_IND expects address")
            addr_frame = frame_for_address(addr)
            stack_push(frame_read_word(addr_frame, addr.addr))
            ip += 1
        elif mnemonic == "STORE_IND":
            val = stack_pop()
            addr = stack_pop()
            if not isinstance(addr, Address):
                raise ValueError("STORE_IND expects address")
            addr_frame = frame_for_address(addr)
            frame_write_word(addr_frame, addr.addr, val)
            ip += 1
        elif mnemonic == "POP":
            stack_pop()
            ip += 1
        elif mnemonic in ("ADD", "SUB", "MUL", "DIV", "REM", "AND_OP", "OR_OP", "LT", "GT", "LE", "GE", "EQ", "NE"):
            b = stack_pop()
            a = stack_pop()
            if mnemonic == "ADD" and (isinstance(a, str) or isinstance(b, str)):
                stack_push(str(a) + str(b))
                ip += 1
                continue
            if mnemonic in ("EQ", "NE") and (isinstance(a, Address) or isinstance(b, Address)):
                av = (a.addr, a.frame_id) if isinstance(a, Address) else a
                bv = (b.addr, b.frame_id) if isinstance(b, Address) else b
                stack_push(1 if ((av == bv) if mnemonic == "EQ" else (av != bv)) else 0)
                ip += 1
                continue
            ai = to_int(a)
            bi = to_int(b)
            if mnemonic == "ADD":
                stack_push(ai + bi)
            elif mnemonic == "SUB":
                stack_push(ai - bi)
            elif mnemonic == "MUL":
                stack_push(ai * bi)
            elif mnemonic == "DIV":
                stack_push(int(ai / bi))
            elif mnemonic == "REM":
                stack_push(ai % bi)
            elif mnemonic == "AND_OP":
                stack_push(1 if (ai and bi) else 0)
            elif mnemonic == "OR_OP":
                stack_push(1 if (ai or bi) else 0)
            elif mnemonic == "LT":
                stack_push(1 if ai < bi else 0)
            elif mnemonic == "GT":
                stack_push(1 if ai > bi else 0)
            elif mnemonic == "LE":
                stack_push(1 if ai <= bi else 0)
            elif mnemonic == "GE":
                stack_push(1 if ai >= bi else 0)
            elif mnemonic == "EQ":
                stack_push(1 if ai == bi else 0)
            elif mnemonic == "NE":
                stack_push(1 if ai != bi else 0)
            ip += 1
        elif mnemonic == "NEG":
            a = stack_pop()
            stack_push(-to_int(a))
            ip += 1
        elif mnemonic == "JMP":
            ip = operands[0]
        elif mnemonic == "JZ":
            val = stack_pop()
            if to_int(val) == 0:
                ip = operands[0]
            else:
                ip += 1
        elif mnemonic == "CALL":
            target = operands[0]
            argc = operands[1]
            if argc < 0:
                raise ValueError("CALL with negative argc")
            if target < 0:
                name = imports[-target - 1]
                args = [stack_pop() for _ in range(argc)][::-1]
                res = builtin_call(name, args)
                stack_push(res)
                ip += 1
            else:
                call_stack.append(CallFrame(ip + 1, bp, len(data_frames)))
                data_frames.append(DataFrame(bytearray(data_template)))
                ip = target
        elif mnemonic in ("RET", "RETF"):
            if not call_stack:
                break
            frame_info = call_stack.pop()
            bp = frame_info.bp
            while len(data_frames) > frame_info.frame_depth:
                data_frames.pop()
            if len(data_frames) < frame_info.frame_depth:
                raise ValueError("call frame stack mismatch")
            ip = frame_info.return_ip
        elif mnemonic == "ENTER":
            bp = sp
            ip += 1
        elif mnemonic == "LEAVE":
            if sp < bp:
                raise ValueError("stack underflow at LEAVE")
            if sp > bp + 1:
                raise ValueError("stack imbalance at LEAVE")
            ret_val = None
            if sp > bp:
                ret_val = stack_pop()
            stack_truncate(bp)
            if ret_val is None:
                ret_val = 0
            stack_push(ret_val)
            if call_stack:
                target_depth = call_stack[-1].frame_depth
                if len(data_frames) > target_depth:
                    data_frames.pop()
            ip += 1
        elif mnemonic == "RANGE_OP":
            _end = stack_pop()
            start = stack_pop()
            stack_push(to_int(start))
            ip += 1
        elif mnemonic == "INDEX":
            idx = stack_pop()
            base = stack_pop()
            if not isinstance(base, Address):
                raise ValueError("INDEX expects address base")
            addr = base.addr + to_int(idx) * word_size
            stack_push(Address(addr, base.frame_id))
            ip += 1
        elif mnemonic == "SET_PORT":
            io_port = to_int(stack_pop())
            ip += 1
        elif mnemonic == "IN":
            if io_port == 0:
                line = sys.stdin.readline()
                if not line:
                    stack_push(0)
                else:
                    stack_push(int(line.strip()))
            else:
                stack_push(0)
            ip += 1
        elif mnemonic == "OUT":
            val = to_int(stack_pop())
            if io_port == 1:
                # Port 1 models raw byte output from the VM.
                sys.stdout.buffer.write(bytes([val & 0xFF]))
                sys.stdout.buffer.flush()
            ip += 1
        else:
            raise ValueError(f"unsupported instruction {mnemonic}")

    if dump_state_path:
        dump_state(dump_state_path, data_frames, data_sizes, meta_bytes)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Run SPO3 VM binary")
    parser.add_argument("-s", "--spec", required=True, help="Path to VM spec.json")
    parser.add_argument("-i", "--input", required=True, help="Input .bin file")
    parser.add_argument("--max-steps", type=int, default=1000000, help="Max VM steps")
    parser.add_argument("--dump-state", help="Write final VM frame state to JSON")
    args = parser.parse_args()

    try:
        spec, by_opcode = load_spec(args.spec)
        binary = parse_binary(args.input, by_opcode)
        return run_vm(binary, spec, by_opcode, args.max_steps, args.dump_state)
    except Exception as exc:
        print(f"vm error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
