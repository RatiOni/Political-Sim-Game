# Ardenia map bible

This is the spatial canon used by the dashboard map. It takes the compact,
mountain-and-coast feel of a Caucasus country as a reference, but is an
original silhouette and an original political geography. It must never become
a traced real-world border.

## The country at a glance

Ardenia is broad east-to-west and compressed north-to-south. A broken northern
mountain wall protects little and separates more. The Kesla comes down through
Karsen, bends across Vashtera and the central plain, then reaches the Aster Sea
near Tavri. The only sea is west and south-west: every other edge of the map is
land, pass or frontier. The coast is warm, commercially useful and difficult
for the state to police.

Veldoria lies beyond the northern passes. Krasova is across the eastern border
of Zavost and Darev, where the old Union industrial system and the Zovar energy
line meet. Merova is beyond the south-eastern lowlands. The western coast is
Ardenian in law; its Vetrenka section is not under Vashtera's control in fact.

## Regional placement and adjacency

| Region | Position | Borders inside Ardenia | Political fact |
|---|---|---|---|
| Anera | north-west highlands | Vashtera, Sela, Vetrenka | poor, devout, armed, weakly governed |
| Karsen | north-central passes | Anera, Vashtera, Zavost | upper Kesla, garrisons and winter roads |
| Vashtera | central-eastern Kesla basin | Karsen, Zavost, Sela, Orvena | capital and administrative core |
| Zavost | east | Karsen, Vashtera, Sela, Darev, Krasova | plants, rail and unions |
| Darev | far east and south-east | Zavost, Sela, Merova, Krasova | energy, garrisons and exposed frontiers |
| Sela | central and southern plain | Vashtera, Zavost, Darev, Kelvet, Orvena | land, grain, roads and rural credit |
| Kelvet | south-west approaches | Sela, Orvena | Tavri, customs and legal/illegal trade |
| Orvena | west-central foothills | Anera, Vashtera, Sela, Kelvet, Vetrenka | loyalist corridor, displaced families and Selvara |
| Vetrenka | western coast | Anera, Orvena | separatist-held territory behind the ceasefire line |

The ceasefire line is **inside** Ardenia's recognised border. It is never to
be rendered as an international boundary or as a normal provincial border.

## Strategic features

- **Kesla corridor:** Karsen headwaters → Vashtera → Sela → Tavri. It is the
  country's natural administrative and transport spine.
- **Vashtera–Duvinsk rail line:** the critical industrial connection to Zavost.
- **Vashtera–Tavri road and rail:** the route from state capacity to customs
  revenue and external trade.
- **Zovar line:** crosses the Krasovan border through Darev and Zavost, then runs westward
  toward the populated core; it is an energy dependency, not a generic map
  decoration.
- **Vetrenka checkpoints:** show closure and tension, not a usable player
  route until the conflict changes.

## Map presentation rules

- The national map is the dashboard's primary map. The rest of the world is
  still simulated, but reached via Diplomacy, the relations panel and
  dispatches rather than a continent board.
- Region borders are useful administrative lines, not clean state-shaped
  blocks. Terrain, river, roads, rail and the ceasefire have equal visual
  importance.
- The nine regional ids in `geography.py` are the stable identifiers for the
  regional simulation. Map coordinates are presentation data only.
