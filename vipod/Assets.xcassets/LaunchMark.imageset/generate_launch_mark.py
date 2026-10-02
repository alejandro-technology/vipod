"""Generate the original 120-point vector launch marks using only Python stdlib."""

from pathlib import Path


OUTPUT = Path(__file__).parent

# Original rounded apple silhouette and detached diagonal leaf, drawn inside the
# requested visual bounds on a 120 x 120 pt canvas. The right contour scoops
# inward for a high, smoothly curved bite; every closed contour ends with h.
PATHS = (
    "60 77 m 55 81 50 83 44 83 c 31 83 22 72 22 58 c 22 43 31 28 43 21 "
    "c 51 16 56 20 61 22 c 66 20 72 16 80 20 c 92 25 99 38 99 49 "
    "c 99 54 96 57 91 59 c 86 61 83 64 84 68 c 85 73 91 74 98 72 "
    "c 93 80 86 83 79 83 c 72 83 67 79 61 78 c 60 78 60 77 60 77 h f",
    "61 89 m 61 98 72 105 94 106 c 89 96 78 90 61 89 h f",
)


def pdf(color: tuple[float, float, float]) -> bytes:
    commands = [
        "q",
        f"{color[0]:.3f} {color[1]:.3f} {color[2]:.3f} rg",
    ]
    commands.extend(PATHS)
    commands.append("Q")
    stream = "\n".join(commands).encode("ascii")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 120 120] /Resources << >> /Contents 4 0 R >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    result = bytearray(b"%PDF-1.4\n% Original VIPOD launch artwork\n")
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(result))
        result.extend(f"{index} 0 obj\n".encode() + obj + b"\nendobj\n")
    xref = len(result)
    result.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        result.extend(f"{offset:010d} 00000 n \n".encode())
    result.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    )
    return bytes(result)


(OUTPUT / "launch-mark-dark.pdf").write_bytes(pdf((0.055, 0.060, 0.065)))
(OUTPUT / "launch-mark-light.pdf").write_bytes(pdf((0.910, 0.920, 0.930)))
