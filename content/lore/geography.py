"""Ardenia's regions, cities, river, and disputed ceasefire line."""

COUNTRY_PROFILE = {
    "id": "ardenia",
    "name": "The shape of Ardenia",
    "body": (
        "Ardenia is a small country that behaves like a large one because it "
        "has never been left alone: roughly 78,000 square kilometres and 6.4 "
        "million people on paper, closer to 6.0 million given who has left. A "
        "mountain spine in the north descends through a wheat plain to a warm, "
        "badly defended coast. Its politics is chiefly the argument among the "
        "six regions laid across that geography."
    ),
}

KESLA = {
    "id": "kesla",
    "name": "The Kesla",
    "body": (
        "The Kesla rises in the northern mountains, runs south-east through "
        "Vashtera, and reaches the sea at Tavri. Ardenians locate more than "
        "places by it: above the Kesla means highland, poor, devout and "
        "Ardenian-speaking; below it means the plain, the towns and the mixed "
        "places."
    ),
}

CEASEFIRE_LINE = {
    "id": "vetrenka_ceasefire_line",
    "name": "The Vetrenka ceasefire line",
    "body": (
        "Since autumn 1992 the Vetrenka Free Front has administered the land "
        "behind a ceasefire line Ardenia does not recognise and cannot cross. "
        "Together with the ungoverned uplands of Anera, roughly a fifth of the "
        "map does not answer to Vashtera."
    ),
}


REGIONS = [
    {
        "id": "vashtera",
        "name": "Vashtera Capital District",
        "body": (
            "The capital and the belt of dormitory towns the Union built around "
            "it hold 1.1 million people, a sixth of the country, and effectively "
            "all of its media, ministries, courts, foreign embassies and hard "
            "currency. What Vashtera decides is not what the country experiences, "
            "and every party outside it says so constantly."
        ),
    },
    {
        "id": "zavost",
        "name": "Zavost",
        "body": (
            "The eastern industrial province was built between 1948 and 1974 "
            "for Union demand that no longer exists: steel, rail rolling stock, "
            "fertiliser and nitrogen works. Kolvenian-speakers are a plurality "
            "in its cities. Zavost has the country's highest unemployment, its "
            "largest body of skilled workers, its only real trade unions, and "
            "the border with Krasova."
        ),
    },
    {
        "id": "sela",
        "name": "The Sela",
        "body": (
            "The central plain grows grain, sunflower and sugar beet. Its 340,000 "
            "hectares of collective farmland were legally dissolved in 1991 and "
            "have been physically contested ever since. This is Agrarian Union "
            "country; it votes on credit terms, fuel prices and roads, in that "
            "order, with little visible interest in anything else."
        ),
    },
    {
        "id": "anera",
        "name": "Anera",
        "body": (
            "The western and north-western highlands are stone villages, sheep, "
            "orchards, monasteries and remittances. Anera is the poorest and most "
            "homogeneously Ardenian region, with the highest church attendance "
            "and the most rifles. It is Dorin Vasca's home. The capital appoints "
            "officials there; they are received politely and largely ignored."
        ),
    },
    {
        "id": "kelvet",
        "name": "The Kelvet Coast",
        "body": (
            "The southern coast holds the ports, fishing fleet, customs houses "
            "and container yards. Roughly nine-tenths of Ardenia's legal trade "
            "and effectively all of its illegal trade passes here. The Falcons "
            "were born on Kelvet, and nobody who governs Ardenia gets to be "
            "squeamish about Tavri."
        ),
    },
    {
        "id": "vetrenka",
        "name": "Vetrenka",
        "body": (
            "The south-western coastal region is twelve per cent of the map, "
            "three per cent of the population, and about a third of the useful "
            "coastline. It has held autonomy under three sovereigns, speaks a "
            "distinct dialect, and has shown no great attachment to Ardenia in "
            "two centuries. It is now governed by the Vetrenka Free Front."
        ),
    },
]


CITIES = [
    {
        "id": "vashtera_city",
        "name": "Vashtera",
        "region_id": "vashtera",
        "body": (
            "Vashtera sits where the Kesla leaves the hills: a Verdan-era core "
            "of yellow stucco and ministries, Kestrel Square before the Chamber, "
            "a Union ring of eleven-storey blocks, and currency kiosks on every "
            "central corner. Heat has been unreliable for two winters and the "
            "trams run when the depot has fuel. It is the whole of the state's "
            "capacity and roughly a quarter of its problems."
        ),
    },
    {
        "id": "duvinsk",
        "name": "Duvinsk / Duvin",
        "region_id": "zavost",
        "body": (
            "Zavost's principal city, about 340,000 people, is a company town "
            "for a country that no longer has the company. It was Duvin before "
            "1938 and is officially Duvinsk now; which name a speaker chooses "
            "tells everyone in the room how they vote."
        ),
    },
    {
        "id": "tavri",
        "name": "Tavri",
        "region_id": "kelvet",
        "body": (
            "The second city, about 290,000 people, is older, warmer and richer "
            "than it declares. Its Osmene-era quarter and Muslim community "
            "predate the Ardenian state; its customs house runs the country's "
            "actual balance of payments."
        ),
    },
    {
        "id": "rovets",
        "name": "Rovets",
        "region_id": "sela",
        "body": (
            "The Sela's largest market town, about 95,000 people, is a grain "
            "exchange, a line of silos, and the Agrarian Union's real capital."
        ),
    },
    {
        "id": "kavor",
        "name": "Kavor",
        "region_id": "anera",
        "body": (
            "A market town of roughly 40,000 beneath a monastery, Kavor is the "
            "last place on the western road where the government's writ is "
            "unambiguous."
        ),
    },
    {
        "id": "ostrena",
        "name": "Ostrena",
        "region_id": "vetrenka",
        "body": (
            "Vetrenka's capital is a port of roughly 55,000 that the Ardenian "
            "state has not entered since September 1992."
        ),
    },
]
