#!/usr/bin/env python3
"""
gen_spv_pas.py

Compile GLSL shaders to SPIR-V (using glslangValidator) and generate a Pascal unit
that embeds the compiled SPV as baked UInt32 arrays suitable for creating
VkShaderModule without reading external files at runtime.

Usage:
  ./gen_spv_pas.py shaders/vert.glsl shaders/frag.glsl src/EmbeddedShaders.pas

Requirements:
  - glslangValidator must be on PATH (comes with the Vulkan SDK).
  - Python 3.

What it does:
  - runs glslangValidator -V shader -o spv/<name>.spv
  - reads the .spv binary and emits a Pascal unit with const arrays of LongWord
    (32-bit little-endian words) and helper accessors (pointer + byte size).
"""
import os
import sys
import struct
import subprocess

def compile_to_spv(src_path, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    cmd = ['glslangValidator', '-V', src_path, '-o', out_path]
    print('Compiling:', ' '.join(cmd))
    subprocess.check_call(cmd)

def read_spv_uint32s(spv_path):
    with open(spv_path, 'rb') as f:
        data = f.read()
    # Ensure length is multiple of 4
    if len(data) % 4 != 0:
        raise RuntimeError('SPV length not multiple of 4: ' + spv_path)
    count = len(data) // 4
    # SPIR-V words are little-endian uint32
    words = list(struct.unpack('<' + 'I'*count, data))
    return words

def write_pas_unit(vert_words, frag_words, out_pas):
    with open(out_pas, 'w', encoding='utf-8') as f:
        f.write('unit EmbeddedShaders;\n\n')
        f.write('{$mode objfpc}{$H+}\n\n')
        f.write('interface\n\n')
        f.write('uses\n  SysUtils;\n\n')
        f.write('const\n')
        f.write('  vert_spv_len = %d;\n' % len(vert_words))
        if len(vert_words) > 0:
            f.write('  vert_spv: array[0..%d] of LongWord = (\n' % (len(vert_words)-1))
            # write in lines of 8 values
            for i in range(0, len(vert_words), 8):
                slice_ = vert_words[i:i+8]
                f.write('    ' + ', '.join('0x%08x' % w for w in slice_))
                if i + 8 < len(vert_words):
                    f.write(',\n')
                else:
                    f.write('\n')
            f.write('  );\n\n')
        else:
            f.write('  vert_spv: array[0..-1] of LongWord = ();\n\n')

        f.write('  frag_spv_len = %d;\n' % len(frag_words))
        if len(frag_words) > 0:
            f.write('  frag_spv: array[0..%d] of LongWord = (\n' % (len(frag_words)-1))
            for i in range(0, len(frag_words), 8):
                slice_ = frag_words[i:i+8]
                f.write('    ' + ', '.join('0x%08x' % w for w in slice_))
                if i + 8 < len(frag_words):
                    f.write(',\n')
                else:
                    f.write('\n')
            f.write('  );\n\n')
        else:
            f.write('  frag_spv: array[0..-1] of LongWord = ();\n\n')

        f.write('function GetVertSpvPtr: Pointer;\n')
        f.write('function GetVertSpvByteSize: NativeUInt;\n')
        f.write('function GetFragSpvPtr: Pointer;\n')
        f.write('function GetFragSpvByteSize: NativeUInt;\n\n')

        f.write('implementation\n\n')

        f.write('function GetVertSpvPtr: Pointer;\nbegin\n')
        if len(vert_words) > 0:
            f.write('  Result := @vert_spv[0];\n')
        else:
            f.write('  Result := nil;\n')
        f.write('end;\n\n')

        f.write('function GetVertSpvByteSize: NativeUInt;\nbegin\n')
        f.write('  Result := vert_spv_len * SizeOf(LongWord);\n')
        f.write('end;\n\n')

        f.write('function GetFragSpvPtr: Pointer;\nbegin\n')
        if len(frag_words) > 0:
            f.write('  Result := @frag_spv[0];\n')
        else:
            f.write('  Result := nil;\n')
        f.write('end;\n\n')

        f.write('function GetFragSpvByteSize: NativeUInt;\nbegin\n')
        f.write('  Result := frag_spv_len * SizeOf(LongWord);\n')
        f.write('end;\n\n')

        f.write('end.\n')

def main(argv):
    if len(argv) != 4:
        print('Usage: gen_spv_pas.py <vert.glsl> <frag.glsl> <out_pas>')
        sys.exit(2)
    vert_src, frag_src, out_pas = argv[1], argv[2], argv[3]
    spv_dir = 'spv'
    vert_spv = os.path.join(spv_dir, 'vert.spv')
    frag_spv = os.path.join(spv_dir, 'frag.spv')

    compile_to_spv(vert_src, vert_spv)
    compile_to_spv(frag_src, frag_spv)

    vert_words = read_spv_uint32s(vert_spv)
    frag_words = read_spv_uint32s(frag_spv)

    write_pas_unit(vert_words, frag_words, out_pas)
    print('Wrote', out_pas)

if __name__ == '__main__':
    main(sys.argv)