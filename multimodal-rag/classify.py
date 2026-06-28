"""Classify conversation turns into semantic types using regex heuristics."""

import re

PATTERNS = [
    ("decision", re.compile(
        r"\b(we (decided|agreed|chose|will go with|going to)|decision:|"
        r"I('ll| will) (use|adopt|switch|drop|go with)|let's go with|"
        r"settled on|picked|opting for)\b", re.IGNORECASE
    )),
    ("milestone", re.compile(
        r"\b(done|finished|completed|deployed|shipped|merged|released|"
        r"working now|fixed it|it works|all (set|good|passing)|"
        r"tests pass|build succeeded)\b", re.IGNORECASE
    )),
    ("problem", re.compile(
        r"\b(error|bug|fail(ed|s|ing)?|broken|crash(ed|es)?|exception|"
        r"issue|not working|can't connect|cannot|stuck|blocked|timeout|"
        r"traceback|stack trace|404|500|502|503)\b", re.IGNORECASE
    )),
    ("preference", re.compile(
        r"\b(prefer|always use|never use|I (like|hate|want|don't want|avoid)|"
        r"my (style|convention|preference)|from now on|stop doing)\b", re.IGNORECASE
    )),
    ("emotional", re.compile(
        r"\b(frustrated|annoyed|excited|happy|worried|stressed|confused|"
        r"tired|great|terrible|love it|hate it|impressed|disappointed)\b", re.IGNORECASE
    )),
]


def classify(text: str) -> str:
    """Return the first matching classification type, or 'general'."""
    for label, pattern in PATTERNS:
        if pattern.search(text):
            return label
    return "general"


def classify_turn(user_text: str, assistant_text: str) -> str:
    """Classify a user+assistant exchange pair."""
    user_cls = classify(user_text)
    if user_cls != "general":
        return user_cls
    return classify(assistant_text)
