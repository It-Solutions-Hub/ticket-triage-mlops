"""Support-ticket triage model: synthetic data generator + scikit-learn pipeline."""
from __future__ import annotations

import random

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline

CATEGORY_PHRASES = {
    "billing": ["I was charged twice", "I need a refund", "the invoice amount is wrong", "my payment failed",
                "credit card was declined", "I was overcharged this month", "please cancel the renewal fee"],
    "technical": ["the app crashes on launch", "I get error 500", "cannot connect to the server",
                  "the dashboard is very slow", "the API returns a timeout", "there is a bug in the export",
                  "the page freezes after loading"],
    "account": ["I need to reset my password", "please change my email address", "my account is locked",
                "the two factor code is not working", "update my profile name", "delete my account",
                "I cannot sign in"],
    "shipping": ["my package was not delivered", "the tracking number is not updating", "wrong address on the parcel",
                 "the delivery is delayed", "the box arrived damaged", "items are missing from my order",
                 "the courier returned my parcel"],
}
OPENERS = ["Hi team,", "Hello,", "Please help.", "This is urgent.", "I contacted you earlier.", ""]
CLOSERS = ["since yesterday.", "for the second time.", "again today.", "this week.", "Thanks in advance.", ""]


def generate_tickets(n_samples: int = 800, seed: int = 42):
    rng = random.Random(seed)
    cats = sorted(CATEGORY_PHRASES)
    texts, labels = [], []
    for _ in range(n_samples):
        cat = rng.choice(cats)
        parts = rng.sample(CATEGORY_PHRASES[cat], k=rng.choice([1, 2]))
        if rng.random() < 0.10:  # label noise: a stray phrase from another category
            other = rng.choice([c for c in cats if c != cat])
            parts.append(rng.choice(CATEGORY_PHRASES[other]))
            rng.shuffle(parts)
        text = " ".join([rng.choice(OPENERS), " and ".join(parts), rng.choice(CLOSERS)]).strip()
        texts.append(text)
        labels.append(cat)
    return texts, labels


def train_and_evaluate(n_samples: int = 800, seed: int = 42):
    texts, labels = generate_tickets(n_samples, seed)
    x_tr, x_te, y_tr, y_te = train_test_split(texts, labels, test_size=0.25, random_state=seed, stratify=labels)
    model = Pipeline([
        ("tfidf", TfidfVectorizer(ngram_range=(1, 2))),
        ("clf", LogisticRegression(max_iter=1000)),
    ])
    model.fit(x_tr, y_tr)
    pred = model.predict(x_te)
    metrics = {
        "accuracy": float(accuracy_score(y_te, pred)),
        "macro_f1": float(f1_score(y_te, pred, average="macro")),
        "n_train": len(x_tr),
        "n_test": len(x_te),
    }
    return model, metrics
