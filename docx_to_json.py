"""Convert the song book `final.docx` into `songs.json`.

Document layout (discovered by inspection):
  * The body contains 152 tables, one table per song, in order.
  * Each table has a single row with two cells:
      - cell 0 -> lyrics (the `content`)
      - cell 1 -> chords (the `accords`)
  * Bold runs in the lyrics mark refrains/choruses and must be preserved.
    They are encoded with Markdown `**bold**` markers in `content`.
  * Empty paragraphs between verses are kept as blank lines.

Song numbering starts at 2 (first song -> number 2).
"""
from __future__ import annotations

import json
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"

DOCX = Path("final.docx")
OUTPUTS = [Path("songs.json"), Path("assets/songs.json")]
START_NUMBER = 2


def run_is_bold(run: ET.Element) -> bool:
    rpr = run.find(f"{W}rPr")
    if rpr is None:
        return False
    b = rpr.find(f"{W}b")
    if b is None:
        return False
    return b.get(f"{W}val") not in ("0", "false", "none")


def paragraph_lines(paragraph: ET.Element) -> list[list[tuple[str, bool]]]:
    """Return the visual lines of a paragraph.

    A paragraph may hold several lines when it contains `<w:br/>` breaks.
    Each line is a list of (text, bold) segments.
    """
    lines: list[list[tuple[str, bool]]] = [[]]
    for run in paragraph.findall(f"{W}r"):
        bold = run_is_bold(run)
        for node in run:
            tag = node.tag
            if tag == f"{W}t":
                lines[-1].append((node.text or "", bold))
            elif tag == f"{W}tab":
                lines[-1].append(("\t", bold))
            elif tag in (f"{W}br", f"{W}cr"):
                lines.append([])
    return lines


def segments_to_markdown(segments: list[tuple[str, bool]]) -> str:
    """Render (text, bold) segments to a Markdown string.

    Bold spans are wrapped with `**` markers, with surrounding whitespace
    moved outside the markers so the Markdown stays valid.
    """
    chars: list[tuple[str, bool]] = []
    for text, bold in segments:
        for ch in text:
            chars.append((ch, bold))

    out: list[str] = []
    i = 0
    n = len(chars)
    while i < n:
        if not chars[i][1]:
            out.append(chars[i][0])
            i += 1
            continue
        j = i
        while j < n and chars[j][1]:
            j += 1
        span = "".join(ch for ch, _ in chars[i:j])
        lead = span[: len(span) - len(span.lstrip())]
        trail = span[len(span.rstrip()):]
        core = span.strip()
        out.append(f"{lead}**{core}**{trail}" if core else span)
        i = j
    # Merge bold spans separated only by whitespace: `**a** **b**` -> `**a b**`.
    merged = re.sub(r"\*\*(\s+)\*\*", r"\1", "".join(out))
    return merged.strip()


def cell_lines(cell: ET.Element, *, with_bold: bool) -> list[str]:
    lines: list[str] = []
    for paragraph in cell.findall(f"{W}p"):
        for segments in paragraph_lines(paragraph):
            if with_bold:
                lines.append(segments_to_markdown(segments))
            else:
                lines.append("".join(text for text, _ in segments).strip())
    return lines


def trim_blank_edges(lines: list[str]) -> list[str]:
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def collapse_blank_runs(lines: list[str]) -> list[str]:
    result: list[str] = []
    for line in lines:
        if not line.strip():
            if result and not result[-1].strip():
                continue
            result.append("")
        else:
            result.append(line)
    return result


def strip_markers(text: str) -> str:
    return text.replace("**", "")


def first_nonempty(lines: list[str]) -> str:
    for line in lines:
        if line.strip():
            return strip_markers(line).strip()
    return ""


def parse() -> list[dict[str, object]]:
    with zipfile.ZipFile(DOCX) as zf:
        xml = zf.read("word/document.xml")
    body = ET.fromstring(xml).find(f"{W}body")

    songs: list[dict[str, object]] = []
    for index, table in enumerate(body.findall(f"{W}tbl")):
        cells = table.findall(f"{W}tr")[0].findall(f"{W}tc")
        content_lines = collapse_blank_runs(
            trim_blank_edges(cell_lines(cells[0], with_bold=True))
        )
        accord_lines = [
            line for line in cell_lines(cells[1], with_bold=False) if line.strip()
        ]

        songs.append(
            {
                "number": START_NUMBER + index,
                "name": first_nonempty(content_lines),
                "accords": "\n".join(accord_lines),
                "content": "\n".join(content_lines),
            }
        )
    return songs


def main() -> int:
    songs = parse()
    payload = json.dumps(songs, ensure_ascii=False, indent=2) + "\n"
    for out in OUTPUTS:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(payload, encoding="utf-8")
    print(f"Wrote {len(songs)} songs to: {', '.join(str(o) for o in OUTPUTS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
