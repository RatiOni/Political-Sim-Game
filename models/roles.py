"""
Canonical political roles — the bridge that lets one authored event speak to
nine differently-shaped party systems.

Every country's factions are its own: Ardenia has a Workers' Front and an
Agrarian Union, Qadir has a Clerical Council and Merchant Houses, Terand has
a Military Bloc. An event that names `workers_front` therefore does nothing
at all outside Ardenia. Roles fix that: content refers to "the labour bloc"
(`ROLE_LABOUR`), and the engine resolves it against whichever faction plays
that part in the country actually being played.

The centroids below are not guesses — they are the cluster means of the 37
authored factions across all nine country files, which fall into six
natural groups:

    labour        econ ≈ -0.63, soc ≈ +0.40   organised left (8 factions)
    business      econ ≈ +0.62, soc ≈ -0.13   capital and commerce (6)
    nationalist   econ ≈ +0.23, soc ≈ -0.77   authoritarian right (6)
    agrarian      econ ≈ -0.20, soc ≈ -0.40   rural and traditional (7)
    reform        econ ≈ +0.17, soc ≈ +0.66   liberal reformers (7)
    establishment econ ≈ +0.27, soc ≈ -0.07   the governing centre (3)

A faction takes the role of its nearest centroid, so classification is
deterministic and every faction gets exactly one role. Not every country
has every role (Solheim has no agrarian party, Terand no labour party) —
`role_faction_id` returns None there and callers skip it, the same way
unknown faction ids already degrade safely.
"""

ROLE_LABOUR = "@labour"
ROLE_BUSINESS = "@business"
ROLE_NATIONALIST = "@nationalist"
ROLE_AGRARIAN = "@agrarian"
ROLE_REFORM = "@reform"
ROLE_ESTABLISHMENT = "@establishment"

ROLES = (ROLE_LABOUR, ROLE_BUSINESS, ROLE_NATIONALIST,
         ROLE_AGRARIAN, ROLE_REFORM, ROLE_ESTABLISHMENT)

# role -> (economic, social) cluster mean across all nine authored countries.
ROLE_CENTROIDS = {
    ROLE_LABOUR:        (-0.63, 0.40),
    ROLE_BUSINESS:      (0.62, -0.13),
    ROLE_NATIONALIST:   (0.23, -0.77),
    ROLE_AGRARIAN:      (-0.20, -0.40),
    ROLE_REFORM:        (0.17, 0.66),
    ROLE_ESTABLISHMENT: (0.27, -0.07),
}

# The axis that DEFINES each role, and which direction is more extreme along
# it. When several factions share a role, the one furthest out on this axis
# takes it: Terand's Military Bloc (social -0.90) speaks for the nationalist
# right over the milder Nationalist Party, and Ardenia's Workers' Front
# (econ -0.90) remains the labour bloc rather than the larger, softer Social
# Democrats — a lot of authored Ardenian content is anchored to it by name.
# Agrarian and establishment have no single defining extreme (they are
# defined by sitting in a particular *region* of the compass), so they fall
# back to the most centroid-typical faction.
ROLE_AXIS = {
    ROLE_LABOUR:      ("economic", -1),
    ROLE_BUSINESS:    ("economic", +1),
    ROLE_NATIONALIST: ("social", -1),
    ROLE_REFORM:      ("social", +1),
    ROLE_AGRARIAN:    None,
    ROLE_ESTABLISHMENT: None,
}

# How far off-centroid a faction may sit and still be pressed into an
# otherwise-empty role (agrarian/establishment, which have no axis test).
MAX_FALLBACK_DISTANCE = 0.80

ROLE_LABELS = {
    ROLE_LABOUR: "labour bloc",
    ROLE_BUSINESS: "business bloc",
    ROLE_NATIONALIST: "nationalist bloc",
    ROLE_AGRARIAN: "agrarian bloc",
    ROLE_REFORM: "reform bloc",
    ROLE_ESTABLISHMENT: "establishment",
}


def is_role_key(key: str) -> bool:
    """Role keys are '@'-prefixed so content can never confuse one with a
    literal faction id."""
    return isinstance(key, str) and key.startswith("@")


def _distance(ideology, centroid) -> float:
    de = ideology.economic - centroid[0]
    ds = ideology.social - centroid[1]
    return (de * de + ds * ds) ** 0.5


def classify(ideology) -> str:
    """The role whose centroid this position sits closest to."""
    return min(ROLES, key=lambda r: _distance(ideology, ROLE_CENTROIDS[r]))


def role_distance(ideology, role: str) -> float:
    centroid = ROLE_CENTROIDS.get(role)
    if centroid is None:
        return float("inf")
    return _distance(ideology, centroid)


def axis_value(ideology, role: str):
    """How far out this position sits along the role's defining axis, signed
    so that larger is always more extreme. None for roles without one."""
    axis = ROLE_AXIS.get(role)
    if axis is None:
        return None
    field, direction = axis
    return getattr(ideology, field) * direction


def eligible_for(ideology, role: str) -> bool:
    """Could this faction stand in for a role its country otherwise lacks?

    Only if it is on the correct side of the defining axis — a party of the
    right can never be pressed into the labour bloc. Roles without an axis
    use proximity instead, so nothing absurd gets conscripted.
    """
    value = axis_value(ideology, role)
    if value is not None:
        return value > 0.0
    return role_distance(ideology, role) <= MAX_FALLBACK_DISTANCE
