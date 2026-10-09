from ticket_model import generate_tickets, train_and_evaluate, CATEGORY_PHRASES


def test_data_is_deterministic():
    assert generate_tickets(50, seed=1) == generate_tickets(50, seed=1)


def test_all_categories_present():
    _, labels = generate_tickets(400)
    assert set(labels) == set(CATEGORY_PHRASES)


def test_model_meets_minimum_quality():
    _, metrics = train_and_evaluate()
    assert metrics["accuracy"] >= 0.80
    assert metrics["macro_f1"] >= 0.80
