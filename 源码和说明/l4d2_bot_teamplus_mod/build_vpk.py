"""Build a single-file Source 1 VPK v1. Python 3; no external dependencies."""
from pathlib import Path
import struct
import zlib


def build(source: Path, output: Path) -> None:
    groups = {}
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        extension = relative.suffix[1:] or ' '
        folder = relative.parent.as_posix()
        if folder == '.':
            folder = ' '
        name = relative.stem if relative.suffix else relative.name
        groups.setdefault(extension, {}).setdefault(folder, []).append((name, path.read_bytes()))
    tree, payload = bytearray(), bytearray()

    def string(value):
        tree.extend(value.encode('utf-8') + b'\0')

    for extension, folders in sorted(groups.items()):
        string(extension)
        for folder, entries in sorted(folders.items()):
            string(folder)
            for name, data in sorted(entries):
                string(name)
                tree.extend(struct.pack('<IHHIIH', zlib.crc32(data), 0, 0x7fff, len(payload), len(data), 0xffff))
                payload.extend(data)
            string('')
        string('')
    string('')
    output.write_bytes(struct.pack('<III', 0x55aa1234, 1, len(tree)) + tree + payload)
    print(f'Built {output.name}: {output.stat().st_size:,} bytes')


if __name__ == '__main__':
    root = Path(__file__).resolve().parent
    build(root / 'source', root / 'bot_teamplus_mod.vpk')
