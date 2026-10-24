#!/usr/bin/env python3
"""Descompressor do formato de ajuda do Microsoft Advisor (magic 'LN', ex.: QBASIC.HLP).

Uso: hlp_extract.py ARQUIVO.HLP [INDICE_DO_TOPICO] [--raw]
  Sem indice: imprime todos os topicos. Com indice: so aquele topico.
  --raw: imprime o fluxo descomprimido com os bytes de controle visiveis.

Cabecalho (little-endian):
  0x00 WORD magic = 0x4E4C (bytes 'LN')    0x08 WORD topicCount
  0x22 DWORD topicMapOffset                0x2E DWORD keywordTableOffset (0 = sem frases)
  0x32 DWORD huffmanOffset (0 = sem Huffman) 0x36 DWORD topicTextOffset

Tabela de frases: 1024 strings contadas (byte de tamanho + dados).
Tabela Huffman: WORDs ate um WORD zero. Arvore: entrada com bit 15 = folha (valor nos 8 bits
baixos); senao, bit 0 -> indice entry>>1, bit 1 -> indice+1. Bits lidos do mais significativo.

Texto do topico: WORD tamanho descomprimido, depois os bytes codificados:
  0x10-0x13 : frase, indice = (codigo & 3) << 8 | parametro
  0x14-0x17 : frase seguida de espaco
  0x18      : sequencia de espacos (parametro = tamanho)
  0x19      : repeticao de um caractere (caractere, depois tamanho)
  0x1A      : byte de controle escapado (saida = parametro)
  demais    : literais

Limitacao: o fluxo mistura texto com blocos de atributos (estilos e hiperlinks). A
separacao de linhas e heuristica: trechos de caracteres imprimiveis com o byte de
comprimento inicial removido quando ele bate com o tamanho do trecho. Os marcadores de
hotspot (0x10/0x11) sao removidos. Os blocos de hiperlink nao sao interpretados.
"""
import itertools
import re
import struct
import sys


def huffman_bits(data, start, table):
    """Gerador de bytes decodificados pela arvore Huffman a partir de data[start:]."""
    bit_pos = 0
    total_bits = (len(data) - start) * 8

    def read_bit():
        nonlocal bit_pos
        if bit_pos >= total_bits:
            raise EOFError
        byte = data[start + bit_pos // 8]
        bit = (byte >> (7 - bit_pos % 8)) & 1
        bit_pos += 1
        return bit

    while True:
        idx = 0
        while True:
            entry = table[idx]
            if entry & 0x8000:
                yield entry & 0xFF
                break
            if read_bit() == 0:
                idx = entry >> 1
            else:
                idx = idx + 1


def load(path):
    data = open(path, 'rb').read()
    if struct.unpack_from('<H', data, 0)[0] != 0x4E4C:
        raise SystemExit('nao e um arquivo LN (Microsoft Advisor)')
    topic_count = struct.unpack_from('<H', data, 0x08)[0]
    topic_map = struct.unpack_from('<I', data, 0x22)[0]
    kw_off = struct.unpack_from('<I', data, 0x2E)[0]
    huff_off = struct.unpack_from('<I', data, 0x32)[0]
    phrases = []
    if kw_off:
        p = kw_off
        for _ in range(1024):
            n = data[p]
            phrases.append(data[p + 1:p + 1 + n])
            p += 1 + n
    table = []
    if huff_off:
        p = huff_off
        while True:
            w = struct.unpack_from('<H', data, p)[0]
            p += 2
            if w == 0:
                break
            table.append(w)
    offsets = [struct.unpack_from('<I', data, topic_map + 4 * i)[0] for i in range(topic_count)]
    return data, phrases, table, offsets


def expand(stream, out_len, phrases):
    """Aplica frases e codigos de controle ao fluxo ja Huffman-decodificado."""
    out = bytearray()
    it = iter(stream)
    while len(out) < out_len:
        try:
            c = next(it)
        except StopIteration:
            break
        if 0x10 <= c <= 0x13:
            out += phrases[((c & 3) << 8) | next(it)]
        elif 0x14 <= c <= 0x17:
            out += phrases[((c & 3) << 8) | next(it)] + b' '
        elif c == 0x18:
            out += b' ' * next(it)
        elif c == 0x19:
            ch = next(it)
            out += bytes([ch]) * next(it)
        elif c == 0x1A:
            out.append(next(it))
        else:
            out.append(c)
    return bytes(out)


def topic_bytes(data, phrases, table, offset):
    out_len = struct.unpack_from('<H', data, offset)[0]
    if table:
        stream = huffman_bits(data, offset + 2, table)
    else:
        stream = iter(data[offset + 2:])
    return expand(stream, out_len, phrases)


def topic_title(text):
    m = re.search(rb':n([\x20-\xff]+)', text)
    return m.group(1).decode('cp437', 'replace').strip() if m else ''


def topic_lines(text):
    """Trechos de texto visiveis; remove o byte de comprimento inicial quando ele confere."""
    lines = []
    for m in re.finditer(rb'[\x20-\xff\x10\x11]+', text):
        run = m.group(0).replace(b'\x10', b'').replace(b'\x11', b'')
        if run.startswith(b':n'):
            continue
        for skip in (1, 2):
            if len(run) > skip and abs(run[skip - 1] - (len(run) - skip)) <= 1:
                run = run[skip:]
                break
        if len(run) <= 1:
            continue
        txt = run.decode('cp437', 'replace')
        # barra de navegacao do topico e restos de graficos da caixa de titulo
        if re.match(r'\s*Contents\s+Index\s+Back\*?\s*$', txt):
            continue
        if len(txt.strip()) <= 2 or (not re.search(r'[A-Za-z0-9]', txt) and '\u2500' not in txt):
            continue
        lines.append(txt)
    return lines


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    raw = '--raw' in sys.argv
    data, phrases, table, offsets = load(args[0])
    only = int(args[1]) if len(args) > 1 else None
    for i, off in enumerate(offsets):
        if only is not None and i != only:
            continue
        text = topic_bytes(data, phrases, table, off)
        if raw:
            print('### %d' % i)
            print(text.decode('cp437', 'replace').encode('unicode_escape').decode())
            continue
        print('### %d %s' % (i, topic_title(text)))
        for line in topic_lines(text):
            print(line)
        print()


if __name__ == '__main__':
    main()
