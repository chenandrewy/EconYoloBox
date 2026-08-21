#!/usr/bin/env python3
# Inputs:
#   - Path to a source PDF file (positional argument).
#   - Destination markdown path (positional argument).
#   - Optional CLI flag `--overwrite` to replace existing output.
# Outputs:
#   - Markdown file written to the provided output path, containing OCR text from the PDF.
#   - Sibling `<stem>_images/` folder with extracted figures (only if the PDF contains any).
# How to run:
# """bash
# python .tools/pdf2md.py temp/example-1.pdf temp/example-1-mistral.md
# python .tools/pdf2md.py temp/example-2.pdf temp/example-2-mistral.md --overwrite
# """

import argparse
import base64
import importlib.machinery
import importlib.util
from pathlib import Path

from mistralai.client import Mistral
from mistralai.client.models.documenturlchunk import DocumentURLChunk

_credentials_path = (
    Path(__file__).resolve().parents[2] / ".credentials" / "get-credentials.py"
)
_credentials_spec = importlib.util.spec_from_loader(
    "get_credentials",
    importlib.machinery.SourceFileLoader("get_credentials", str(_credentials_path)),
)
_credentials = importlib.util.module_from_spec(_credentials_spec)
_credentials_spec.loader.exec_module(_credentials)


def _extract_and_relink_images(
    markdown_text: str, image_chunks, images_dir: Path
) -> str:
    """Save image chunks to ``images_dir`` and rewrite links to relative paths."""
    images_dir.mkdir(parents=True, exist_ok=True)
    for img in image_chunks:
        payload = img.image_base64
        if payload.startswith("data:"):
            payload = payload.split(",", 1)[1]
        (images_dir / img.id).write_bytes(base64.b64decode(payload))
        markdown_text = markdown_text.replace(
            f"![{img.id}]({img.id})",
            f"![{img.id}]({images_dir.name}/{img.id})",
        )
    return markdown_text


def resolve_api_key(var_name: str = "MISTRAL_API_KEY") -> str:
    """Return the Mistral API key from the shared credential resolver."""
    api_key = _credentials.get_credential(var_name, "mistral-api-key")
    if api_key:
        return api_key

    raise SystemExit(
        f"{var_name} not found; run `python .credentials/setup.py` on the host "
        "and reopen the container or rerun its host-side injector."
    )


def convert_pdf_to_markdown(
    client: Mistral,
    pdf_path: Path,
    *,
    images_dir: Path,
) -> str:
    """Upload a PDF to Mistral OCR and return combined markdown."""
    upload = client.files.upload(
        file={"file_name": pdf_path.stem, "content": pdf_path.read_bytes()},
        purpose="ocr",
    )
    signed = client.files.get_signed_url(file_id=upload.id, expiry=1)
    response = client.ocr.process(
        document=DocumentURLChunk(document_url=signed.url),
        model="mistral-ocr-latest",
        include_image_base64=True,
    )

    pages = []
    for page in response.pages:
        markdown_text = page.markdown
        if page.images:
            markdown_text = _extract_and_relink_images(
                markdown_text, page.images, images_dir
            )
        pages.append(markdown_text)
    return "\n\n".join(pages)


def write_markdown(markdown_text: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(markdown_text, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a PDF to Markdown via Mistral OCR",
    )
    parser.add_argument("pdf", type=Path, help="Path to the input PDF file")
    parser.add_argument("markdown", type=Path, help="Path to the output markdown file")
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite the markdown file if it already exists.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    pdf_path = args.pdf
    if not pdf_path.is_file():
        raise SystemExit(f"Input PDF not found: {pdf_path}")

    markdown_path = args.markdown
    if markdown_path.exists() and not args.overwrite:
        raise SystemExit(
            "Output markdown already exists; rerun with --overwrite to replace it."
        )

    images_dir = markdown_path.parent / f"{markdown_path.stem}_images"

    api_key = resolve_api_key()
    client = Mistral(api_key=api_key)

    try:
        markdown_text = convert_pdf_to_markdown(
            client,
            pdf_path,
            images_dir=images_dir,
        )
    except Exception as exc:  # noqa: BLE001 - surface underlying OCR failures.
        raise SystemExit(f"OCR request failed: {exc}") from exc

    write_markdown(markdown_text, markdown_path)


if __name__ == "__main__":
    main()
