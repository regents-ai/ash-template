"""Local identity/note acceptance bridge to the EXISTING Regents CLI SIWA signer.

Reads {input, request} from stdin; returns {input, request, proof} for the named
native WebMCP tool. It sends no product request and creates no key. Never log
its output in a public report. This fixture is not a hosted signing endpoint.
"""
import argparse
import json
import sys
from urllib.parse import urlsplit
from uuid import UUID

from regents_cli import siwa
from regents_cli.http import Request


def checked(payload: dict, origin: str) -> Request:
    url = urlsplit(origin)
    if (url.scheme != "http" or url.hostname not in ("localhost", "127.0.0.1")
            or url.username or url.password or url.path or url.query or url.fragment):
        raise ValueError("Only an explicit local fixture origin is permitted")
    if set(payload) != {"input", "request"}:
        raise ValueError("Expected only input and request")
    inputs, prepared = payload["input"], payload["request"]
    if not isinstance(inputs, dict) or not isinstance(prepared, dict):
        raise ValueError("Expected objects")
    operation = prepared.get("operation")
    body = None
    method, path = "GET", "/tools/notes"
    if operation == "agent_whoami":
        if inputs:
            raise ValueError("The identity probe takes no fields")
        path = "/api/agents/v1/whoami"
    elif operation == "notes_create":
        if not {"title", "operation_id"} <= inputs.keys() <= {"title", "operation_id", "body"}:
            raise ValueError("Expected note title, stable operation_id and optional body")
        if not all(isinstance(value, str) for value in inputs.values()):
            raise ValueError("Note fields must be strings")
        UUID(inputs["operation_id"])
        if not 1 <= len(inputs["title"]) <= 120 or len(inputs.get("body", "")) > 10000:
            raise ValueError("Note exceeds its manifest bounds")
        method, body = "POST", inputs
    elif operation == "notes_get":
        if set(inputs) != {"id"} or str(UUID(inputs["id"])) != inputs["id"]:
            raise ValueError("Expected one canonical note UUID")
        path += "/" + inputs["id"]
    elif operation != "notes_list" or inputs:
        raise ValueError("Only the local identity probe and three note acceptance operations are permitted")
    request = Request(method, path, body=body)
    expected = {"operation": operation, "audience": "ash-template", "origin": origin,
                "method": method, "path": path}
    if request.content is not None:
        expected["body"] = request.content.decode("utf-8")
    if prepared != expected:
        raise ValueError("Prepared request mismatch; exact bytes must survive the signer bridge")
    return request


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", required=True)
    args = parser.parse_args()
    text = sys.stdin.read(65_537)
    if len(text) > 65_536:
        raise ValueError("Input too large")
    payload = json.loads(text)
    request = checked(payload, args.origin)
    # Canonical signer handles receipt renewal and signing. No protocol copy.
    proof = siwa.sign(request, siwa.current("ash-template", 30_000))
    print(json.dumps({**payload, "proof": proof}, ensure_ascii=False))


if __name__ == "__main__":
    main()
