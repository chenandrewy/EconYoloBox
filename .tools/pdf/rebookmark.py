#!/usr/bin/env python3
"""
Inputs:
    - Input PDF path (str) passed as the first command-line argument.
    - Output PDF path (str) passed as the second command-line argument.

Outputs:
    - A new PDF written to the output path with regenerated section bookmarks plus
      bookmarks for every detected figure and table caption.

How to run:
    python .tools/rebookmark.py input.pdf output.pdf

Examples:
    python .tools/rebookmark.py temp/test.pdf temp/test_bookmarked.pdf

PDF Rebookmarker with LLM Section Detection

Removes existing bookmarks from a PDF and rebuilds them using:
    - The configured OpenRouter model for main section headings.
    - The configured OpenRouter model for figure captions.
    - Local heuristics for references, appendices, and table captions.

Dependencies:
    pip install pikepdf PyMuPDF openai

Credentials and environment:
    OPENROUTER_API_KEY - Optional per-command override; otherwise read through
        .credentials/get-credentials.py
    OPENROUTER_MODEL - Optional model override (defaults to google/gemini-2.5-flash)
"""

import json
import importlib.machinery
import importlib.util
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import fitz  # PyMuPDF
import pikepdf
from openai import OpenAI

_credentials_path = (
    Path(__file__).resolve().parents[2] / ".credentials" / "get-credentials.py"
)
_credentials_spec = importlib.util.spec_from_loader(
    "get_credentials",
    importlib.machinery.SourceFileLoader("get_credentials", str(_credentials_path)),
)
_credentials = importlib.util.module_from_spec(_credentials_spec)
_credentials_spec.loader.exec_module(_credentials)

# Configuration
MODEL_NAME = os.getenv("OPENROUTER_MODEL", "google/gemini-2.5-flash")

FIGURE_PATTERN = re.compile(
    r"^(?:figure|fig\.?|figura)\s*(?:[A-Z]*[-\s]?\d+(?:[.\-]\d+)*|[IVXLC]+)\b.*",
    re.IGNORECASE,
)

ADDITIONAL_SECTION_RULES = [
    {
        "key": "references",
        "canonical_title": "References",
        "patterns": [
            re.compile(r"^(?:\d+[\.)]\s*)?(references|reference list|bibliography|works cited)\b", re.IGNORECASE)
        ],
        "tail_ratio": 0.5,
        "multiple": False,
    },
    {
        "key": "appendix",
        "canonical_title": None,
        "patterns": [
            re.compile(r"^(appendix|appendices)\b(?:[\s:-].*)?", re.IGNORECASE),
            re.compile(r"^(appendix\s+[A-Z0-9]+)\b(?:[\s:-].*)?", re.IGNORECASE),
        ],
        "tail_ratio": 0.5,
        "multiple": True,
    },
    {
        "key": "table_caption",
        "canonical_title": None,
        "patterns": [
            re.compile(r"^(?:table|tab\.?|tbl\.?)\s*(?:[A-Z]*\d+(?:[.\-]\d+)*|[IVXLC]+)\b.*", re.IGNORECASE),
        ],
        "tail_ratio": 1.0,
        "multiple": True,
    },
]


class SectionDetector:
    """Uses an OpenRouter model to detect main section headers in PDF text."""

    def __init__(self, api_key: str):
        self.client = OpenAI(
            api_key=api_key,
            base_url="https://openrouter.ai/api/v1"
        )
    
    def identify_sections(self, page_texts: List[Tuple[int, str]]) -> List[Dict]:
        """
        Identify main sections from page texts using LLM.
        
        Args:
            page_texts: List of (page_number, text_content) tuples
            
        Returns:
            List of section dicts with 'title' and 'page' keys
        """
        # Prepare text for LLM
        text_blocks = []
        for page_num, text in page_texts:
            text_blocks.append(f"=== PAGE {page_num + 1} ===\n{text}\n")
        
        combined_text = "\n".join(text_blocks)
        
        # Simplified prompt focusing only on major sections
        prompt = f"""Find ONLY the main section headers in this document. Focus on major structural sections like:
- 1 Introduction
- 2 Methodology / Methods
- 3 Results / Findings
- 4 Discussion
- 5 Conclusion

Preserve the section numbers in the title (e.g. "1. Introduction")
Ignore subsections (e.g. "1.1 Sample Splitting"), numbered lists, and paragraphs that refer to sections.

Text to analyze:
{combined_text}

Return ONLY a JSON array:
[{{"title": "Section Title", "page": 1}}]
"""

        try:
            response = self.client.chat.completions.create(
                model=MODEL_NAME,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1,
                max_tokens=1500
            )

            response_text = response.choices[0].message.content.strip()
            
            # Extract JSON from response
            json_match = re.search(r'\[.*\]', response_text, re.DOTALL)
            if json_match:
                json_str = json_match.group(0)
                sections = json.loads(json_str)
                
                # Simple validation
                validated_sections = []
                for section in sections:
                    if isinstance(section, dict) and 'title' in section and 'page' in section:
                        page_idx = section['page'] - 1
                        if 0 <= page_idx < len(page_texts):
                            validated_sections.append({
                                'title': section['title'].strip(),
                                'page': page_idx
                            })
                
                return validated_sections
            else:
                print(f"Warning: Could not parse JSON from LLM response")
                return []
                
        except Exception as e:
            print(f"Error calling OpenRouter API: {e}")
            return []


class FigureDetector:
    """Uses an OpenRouter model to detect figure captions."""

    def __init__(self, api_key: str):
        self.client = OpenAI(
            api_key=api_key,
            base_url="https://openrouter.ai/api/v1"
        )

    def _extract_candidates(self, page_texts: List[Tuple[int, str]]) -> List[Dict]:
        """Gather potential figure lines with small context windows."""
        candidates: List[Dict] = []
        for page_idx, text in page_texts:
            lines = text.splitlines()
            for line_idx, raw_line in enumerate(lines):
                normalized = normalize_heading(raw_line)
                if not normalized:
                    continue
                if not FIGURE_PATTERN.match(normalized):
                    continue

                prev_line = lines[line_idx - 1].strip() if line_idx > 0 else ""
                next_line = lines[line_idx + 1].strip() if line_idx + 1 < len(lines) else ""
                candidates.append({
                    "page": page_idx,
                    "text": normalized,
                    "previous": prev_line,
                    "next": next_line
                })
        return candidates

    def identify_figures(self, page_texts: List[Tuple[int, str]]) -> List[Dict]:
        """
        Identify figure captions from candidate text snippets using the LLM.

        Args:
            page_texts: List of (page_number, text_content) tuples

        Returns:
            List of figure dicts with 'title' and 'page' keys
        """
        candidates = self._extract_candidates(page_texts)
        if not candidates:
            return []

        candidate_descriptions = []
        for idx, candidate in enumerate(candidates, start=1):
            lines = [
                f"Candidate {idx}:",
                f"Page: {candidate['page'] + 1}",
                f"Line: {candidate['text']}",
            ]
            if candidate['previous']:
                lines.append(f"Previous line: {candidate['previous']}")
            if candidate['next']:
                lines.append(f"Next line: {candidate['next']}")
            candidate_descriptions.append("\n".join(lines))

        formatted_candidates = "\n\n".join(candidate_descriptions)

        prompt = f"""You are given candidate lines extracted from a PDF. Decide which lines are TRUE figure captions.

Rules:
- A figure caption is the standalone descriptive text that accompanies a figure, usually beginning with \"Figure\" or \"Fig.\" followed by a number and a colon or dash.
- Captions typically stand alone outside of regular paragraphs. References like \"Figure 1 shows...\" inside the body text are NOT captions.
- Only choose from the provided candidates. If no candidate is a real caption, return an empty list.

Return ONLY a JSON array of confirmed captions using 1-based page numbers:
[{{"title": "Figure 1: Caption text", "page": 3}}]

Candidates:
{formatted_candidates}
"""

        try:
            response = self.client.chat.completions.create(
                model=MODEL_NAME,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1,
                max_tokens=2000
            )

            response_text = response.choices[0].message.content.strip()

            fence_match = re.match(r"^```(?:json)?\s*\n?(.*?)\n?```\s*$", response_text, re.DOTALL)
            if fence_match:
                response_text = fence_match.group(1).strip()

            json_match = re.search(r'\[.*\]', response_text, re.DOTALL)
            if not json_match:
                print("Warning: Could not parse JSON from figure detection response")
                return []

            json_str = json_match.group(0)
            figures = json.loads(json_str)

            validated_figures = []
            for figure in figures:
                if not isinstance(figure, dict):
                    continue
                title = figure.get('title', '').strip()
                page_number = figure.get('page')
                if not title or not isinstance(page_number, int):
                    continue
                page_idx = page_number - 1
                if 0 <= page_idx < len(page_texts):
                    validated_figures.append({
                        'title': title,
                        'page': page_idx
                    })

            return validated_figures
        except Exception as e:
            print(f"Error calling OpenRouter API for figures: {e}")
            return []







def extract_text_by_page(pdf_path: Path) -> List[Tuple[int, str]]:
    """Extract text from each page of the PDF."""
    page_texts = []
    
    with fitz.open(pdf_path) as doc:
        for page_num, page in enumerate(doc):
            text = page.get_text("text")
            page_texts.append((page_num, text))
    
    return page_texts


def normalize_heading(text: str) -> str:
    """Collapse whitespace in potential heading text."""
    return re.sub(r"\s+", " ", text.strip())


def is_heading_candidate(text: str) -> bool:
    """Heuristic filter to identify lines that look like section headings."""
    if not text:
        return False
    if len(text) > 120:
        return False
    if len(text.split()) > 12:
        return False
    return any(char.isalpha() for char in text)


def find_rule_matches(page_texts: List[Tuple[int, str]], rule: Dict) -> List[Tuple[int, str]]:
    """Locate headings that satisfy a particular rule."""
    matches: List[Tuple[int, str]] = []
    total_pages = len(page_texts)
    tail_ratio = rule.get("tail_ratio", 1.0)
    start_index = max(0, int(total_pages * (1 - tail_ratio)))
    seen_on_page: Dict[int, set[str]] = {}

    for page_idx in range(start_index, total_pages):
        _, text = page_texts[page_idx]
        lines = text.splitlines()
        for raw_line in lines:
            normalized = normalize_heading(raw_line)
            if not is_heading_candidate(normalized):
                continue

            lowered = normalized.lower()
            if rule["key"] in {"tables", "table_caption"} and "table of contents" in lowered:
                continue

            for pattern in rule["patterns"]:
                if pattern.match(normalized):
                    page_seen = seen_on_page.setdefault(page_idx, set())
                    lowered_heading = normalized.lower()
                    if lowered_heading in page_seen:
                        break
                    page_seen.add(lowered_heading)
                    matches.append((page_idx, normalized))
                    break
            else:
                continue

            if not rule.get("multiple", False):
                break
        if matches and not rule.get("multiple", False):
            break

    return matches


def detect_additional_sections(page_texts: List[Tuple[int, str]], existing_sections: List[Dict]) -> List[Dict]:
    """Add bookmarks for references, appendices, and table captions when found."""
    existing_titles = {
        section['title'].strip().lower()
        for section in existing_sections
    }
    additional_sections: List[Dict] = []

    for rule in ADDITIONAL_SECTION_RULES:
        matches = find_rule_matches(page_texts, rule)
        if not matches:
            continue

        if not rule.get("multiple", False):
            page_idx, matched_title = matches[0]
            title = rule.get("canonical_title") or matched_title
            normalized_title = title.strip()
            if normalized_title.lower() in existing_titles:
                continue
            additional_sections.append({
                'title': normalized_title,
                'page': page_idx
            })
            existing_titles.add(normalized_title.lower())
        else:
            for page_idx, matched_title in matches:
                if rule["key"] == "table_caption":
                    num_match = re.search(
                        r"(?:table|tab\.?|tbl\.?)\s*([A-Z]*\d+(?:[.\-]\d+)*|[IVXLC]+)",
                        matched_title,
                        re.IGNORECASE,
                    )
                    title = f"Tab {num_match.group(1).rstrip(':. ')}" if num_match else matched_title
                else:
                    title = rule.get("canonical_title") or matched_title
                normalized_title = title.strip()
                if normalized_title.lower() in existing_titles:
                    continue
                additional_sections.append({
                    'title': normalized_title,
                    'page': page_idx
                })
                existing_titles.add(normalized_title.lower())

    return additional_sections


def simplify_figure_titles(figure_sections: List[Dict]) -> List[Dict]:
    """Convert verbose LLM captions into short Fig labels."""
    simplified: List[Dict] = []
    sequential_counter = 0
    for section in sorted(figure_sections, key=lambda x: x['page']):
        title = section.get('title', '')
        match = FIGURE_PATTERN.search(title)
        if match:
            label = match.group(0)
            number_match = re.search(
                r"(?:figure|fig\.?|figura)\s*([A-Z]*[-\s]?\d+(?:[.\-]\d+)*|[IVXLC]+)",
                label,
                re.IGNORECASE,
            )
            if number_match:
                figure_id = number_match.group(1).rstrip(":. ")
            else:
                sequential_counter += 1
                figure_id = str(sequential_counter)
        else:
            sequential_counter += 1
            figure_id = str(sequential_counter)
        simplified.append({
            'title': f"Fig {figure_id}",
            'page': section['page']
        })
    return simplified


def merge_and_deduplicate_sections(*section_lists: List[Dict]) -> List[Dict]:
    """Merge multiple section lists and deduplicate by title while preserving page order."""
    combined: List[Dict] = []
    for sections in section_lists:
        if sections:
            combined.extend(sections)
    seen_titles: set[str] = set()
    merged_sections: List[Dict] = []
    for section in sorted(combined, key=lambda x: x['page']):
        title_lower = section['title'].strip().lower()
        if title_lower in seen_titles:
            continue
        seen_titles.add(title_lower)
        merged_sections.append(section)
    return merged_sections


def process_pdf_simplified(pdf_path: Path, detector: SectionDetector, figure_detector: Optional[FigureDetector] = None) -> List[Dict]:
    """Process entire PDF in single pass focusing on main sections."""
    page_texts = extract_text_by_page(pdf_path)
    
    print(f"Processing {len(page_texts)} pages in single pass...")
    
    # Process all pages at once
    main_sections = detector.identify_sections(page_texts)
    print(f"Found {len(main_sections)} sections")

    unique_sections = merge_and_deduplicate_sections(main_sections)

    figure_sections: List[Dict] = []
    if figure_detector:
        figure_sections = figure_detector.identify_figures(page_texts)
        if figure_sections:
            figure_sections = simplify_figure_titles(figure_sections)
            print(f"Found {len(figure_sections)} figure captions")

    combined_existing = merge_and_deduplicate_sections(unique_sections, figure_sections)
    additional_sections = detect_additional_sections(page_texts, combined_existing)

    return merge_and_deduplicate_sections(unique_sections, figure_sections, additional_sections)


def rebuild_bookmarks(input_path: Path, output_path: Path, sections: List[Dict]) -> None:
    """Remove existing bookmarks and add new ones based on detected sections."""
    outlines: List[pikepdf.OutlineItem] = []

    if sections:
        for section in sections:
            try:
                # Use 0-based page indexing for pikepdf (already converted from 1-based)
                outlines.append(pikepdf.OutlineItem(
                    title=section['title'],
                    destination=section['page']
                ))
            except (IndexError, KeyError) as e:
                print(f"Warning: Could not add bookmark '{section['title']}': {e}")

    with pikepdf.open(input_path) as pdf:
        with pdf.open_outline() as outline:
            outline.root.clear()
            if outlines:
                outline.root.extend(outlines)

        pdf.save(output_path)


def main():
    if len(sys.argv) != 3:
        print("Usage: python .tools/rebookmark.py input.pdf output.pdf")
        sys.exit(1)
    
    input_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2])
    
    if not input_file.exists():
        print(f"Error: Input file '{input_file}' not found")
        sys.exit(1)
    
    # Check for API key
    api_key = _credentials.get_credential(
        "OPENROUTER_API_KEY",
        "openrouter-api-key",
    )
    if not api_key:
        print("Error: OPENROUTER_API_KEY credential not available")
        print(
            "Run `python .credentials/setup.py` on the host, then reopen the "
            "container or rerun its host-side injector."
        )
        sys.exit(1)
    
    print(f"Processing {input_file}...")
    
    # Initialize detectors
    section_detector = SectionDetector(api_key)
    figure_detector = FigureDetector(api_key)
    
    # Process PDF and identify sections
    sections = process_pdf_simplified(input_file, section_detector, figure_detector)
    
    if not sections:
        print("Warning: No sections detected")
    else:
        print(f"\nDetected {len(sections)} sections:")
        for section in sections:
            print(f"  Page {section['page'] + 1}: {section['title']}")
    
    # Rebuild bookmarks
    print(f"\nRebuilding bookmarks in {output_file}...")
    rebuild_bookmarks(input_file, output_file, sections)
    
    print(f"✓ Complete! {len(sections)} bookmarks added to {output_file}")


if __name__ == "__main__":
    main()
