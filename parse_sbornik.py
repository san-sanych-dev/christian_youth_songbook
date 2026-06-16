from __future__ import annotations

import html
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


PDF = Path("сборник песен2_251207_141214-1.pdf")
BBOX = PDF.with_suffix(".bbox.html")
OUTPUT = Path("songs.json")

HEADER = "Сборник молодёжных песен"

CHORD_ATOM = r"[A-GHН](?:[#b])?(?:m|maj|min|sus|dim|aug)?\d*"
CHORD_RE = re.compile(rf"^\(?(?:{CHORD_ATOM})(?:/(?:{CHORD_ATOM}))?(?:-(?:{CHORD_ATOM})(?:/(?:{CHORD_ATOM}))?)*\)?$")
CHORD_FRAGMENT_RE = re.compile(r"^(?:[#b]m?|m|sus|maj|min|dim|aug|\d+)$")


@dataclass(frozen=True)
class Word:
    text: str
    x_min: float
    x_max: float
    y_min: float
    y_max: float

    @property
    def x_center(self) -> float:
        return (self.x_min + self.x_max) / 2


def ensure_bbox() -> None:
    subprocess.run(
        ["pdftotext", "-bbox-layout", str(PDF), str(BBOX)],
        check=True,
    )


def strip_namespace(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def attr_float(node: ET.Element, name: str) -> float:
    return float(node.attrib[name])


def page_words(page: ET.Element) -> list[list[Word]]:
    lines: list[list[Word]] = []
    for line in page.iter():
        if strip_namespace(line.tag) != "line":
            continue

        words: list[Word] = []
        for node in line:
            if strip_namespace(node.tag) != "word":
                continue
            text = html.unescape("".join(node.itertext())).strip()
            if not text:
                continue
            words.append(
                Word(
                    text=text,
                    x_min=attr_float(node, "xMin"),
                    x_max=attr_float(node, "xMax"),
                    y_min=attr_float(node, "yMin"),
                    y_max=attr_float(node, "yMax"),
                )
            )

        if words:
            lines.append(sorted(words, key=lambda word: word.x_min))
    return lines


def normalize_chord_token(token: str) -> str:
    return token.replace("Н", "H")


def is_chord(token: str) -> bool:
    token = token.replace("Н", "H")
    compact = token.strip(".,;:!?'\"“”«»")
    return bool(CHORD_RE.match(compact))


def is_chord_fragment(token: str) -> bool:
    compact = token.strip(".,;:!?'\"“”«»")
    return bool(CHORD_FRAGMENT_RE.match(compact))


def split_content_and_chords(words: list[Word]) -> tuple[str, str]:
    content_tokens: list[str] = []
    chord_tokens: list[str] = []

    for word in words:
        token = word.text.strip(".,;:!?'\"“”«»")
        if is_chord(token):
            chord_tokens.append(normalize_chord_token(token))
        elif chord_tokens and is_chord_fragment(token):
            chord_tokens[-1] += normalize_chord_token(token)
        else:
            content_tokens.append(word.text)

    return " ".join(content_tokens).strip(), " ".join(chord_tokens).strip()


def footer_number(lines: list[list[Word]], side: str, half_page_width: float) -> int | None:
    candidates: list[tuple[float, int]] = []
    for words in lines:
        side_words = [
            word
            for word in words
            if (word.x_center < half_page_width if side == "left" else word.x_center >= half_page_width)
        ]
        if not side_words:
            continue
        text = " ".join(word.text for word in side_words)
        if re.fullmatch(r"\d+", text) and max(word.y_max for word in side_words) > 540:
            candidates.append((max(word.y_max for word in side_words), int(text)))
    if not candidates:
        return None
    return max(candidates)[1]


def extract_side(lines: list[list[Word]], side: str, half_page_width: float) -> tuple[list[str], list[str]]:
    content_lines: list[str] = []
    chord_lines: list[str] = []

    for words in lines:
        selected = [
            word
            for word in words
            if (word.x_center < half_page_width if side == "left" else word.x_center >= half_page_width)
        ]
        if not selected:
            continue

        text = " ".join(word.text for word in selected).strip()
        y_max = max(word.y_max for word in selected)

        if text == HEADER or (re.fullmatch(r"\d+", text) and y_max > 540):
            continue

        content, chords = split_content_and_chords(selected)
        if content and not chords and all(is_chord_fragment(token) for token in content.split()) and chord_lines:
            fragment = "".join(normalize_chord_token(token) for token in content.split())
            if fragment == "#":
                chord_lines[-1] = re.sub(r"\b([A-GH])m\b", r"\1#m", chord_lines[-1], count=1)
            else:
                chord_lines[-1] += fragment
            continue

        if content:
            content_lines.append(content)
        if chords:
            chord_lines.append(chords)

    return trim_blank_lines(content_lines), trim_blank_lines(chord_lines)


def trim_blank_lines(lines: list[str]) -> list[str]:
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def parse() -> list[dict[str, object]]:
    ensure_bbox()
    root = ET.parse(BBOX).getroot()
    pages = [node for node in root.iter() if strip_namespace(node.tag) == "page"]

    songs: list[dict[str, object]] = []
    for page in pages[1:]:
        half_page_width = attr_float(page, "width") / 2
        lines = page_words(page)
        left_number = footer_number(lines, "left", half_page_width)
        right_number = footer_number(lines, "right", half_page_width)

        # The song section ends before the table of contents, whose first spread is 168/169.
        if left_number is not None and left_number >= 168:
            break

        for side, number in (("left", left_number), ("right", right_number)):
            if number is None:
                continue
            content_lines, chord_lines = extract_side(lines, side, half_page_width)
            if not content_lines:
                continue
            songs.append(
                {
                    "number": number,
                    "accords": "\n".join(chord_lines),
                    "content": "\n".join(content_lines),
                }
            )

    return sorted(songs, key=lambda song: int(song["number"]))


def main() -> int:
    if not PDF.exists():
        print(f"PDF not found: {PDF}", file=sys.stderr)
        return 1

    songs = parse()
    OUTPUT.write_text(
        json.dumps(songs, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(songs)} songs to {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
