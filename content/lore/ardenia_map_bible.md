# Ardenia map bible

This is the spatial canon used by the dashboard map. It takes the compact,
mountain-and-coast feel of a Caucasus country as a reference, but is an
original silhouette and an original political geography. It must never become
a traced real-world border.

## The country at a glance

Ardenia is broad east-to-west and compressed north-to-south. A broken northern
mountain wall protects little and separates more. The Kesla comes down from
those mountains, passes through Vashtera and the central plain, then reaches
the sea at Tavri. The southern and western shore is warm, commercially useful,
and difficult for the state to police.

Veldoria lies beyond the northern passes. Krasova is across the eastern border
of Zavost, where the old Union industrial system and the Zovar energy line
meet. Merova is beyond the south-eastern lowlands. The coast is Ardenian in
law; Vetrenka is not under Vashtera's control in fact.

## Regional placement and adjacency

| Region | Position | Borders inside Ardenia | Political fact |
|---|---|---|---|
| Anera | north-west highlands | Vashtera, Sela, Vetrenka | poor, devout, armed, weakly governed |
| Vashtera | north-central Kesla valley | Anera, Sela, Zavost | capital and administrative core |
| Zavost | east | Vashtera, Sela, Kelvet, Krasova | plants, rail, unions and the eastern frontier |
| Sela | central plain | Anera, Vashtera, Zavost, Kelvet, Vetrenka | land, grain, roads and rural credit |
| Kelvet | south and south-east coast | Sela, Zavost, Vetrenka | Tavri, customs and legal/illegal trade |
| Vetrenka | south-west coast | Anera, Sela, Kelvet | separatist-held territory behind the ceasefire line |

The ceasefire line is **inside** Ardenia's recognised border. It is never to
be rendered as an international boundary or as a normal provincial border.

## Strategic features

- **Kesla corridor:** northern headwaters → Vashtera → Sela → Tavri. It is the
  country's natural administrative and transport spine.
- **Vashtera–Duvinsk rail line:** the critical industrial connection to Zavost.
- **Vashtera–Tavri road and rail:** the route from state capacity to customs
  revenue and external trade.
- **Zovar line:** crosses the Krasovan border into Zavost, then runs westward
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
- The six regional ids in `geography.py` remain the stable identifiers for
  future regional simulation. Map coordinates are presentation data only.
