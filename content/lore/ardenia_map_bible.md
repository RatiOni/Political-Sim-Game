# Ardenia map bible

This is the spatial canon used by the dashboard map. It takes the compact,
mountain-and-coast feel of a Caucasus country as a reference, but is an
original silhouette and an original political geography. It must never become
a traced real-world border. No real place name is used.

## The country at a glance

Ardenia is broad east-to-west and compressed north-to-south: a wide, rounded
country with the sea on the west and the capital, Vashtera, in the centre. A
broken northern mountain wall, snow-capped along its whole length, protects
little and separates more; it is notched by passes and folds into a lost valley
above Zavost. The west coast is a worked one: Ostrena's headland under the
wall, the deep Orvena bay that leaves only a narrow waist south of Vetrenka,
and the Kesla estuary at Tavri. The southern frontier is a wandering lowland
edge under low southern hills, until the ruled Merova survey line takes over in
the south-east and climbs toward the Krasovan border. The eastern frontier is
the short, straight Krasovan survey line, two segments meeting at one corner.

The east was drawn out a little beyond the older survey to make room for
Kostrel: the steppe and orchard country east of the Sela, around Rovets, now
stands as a region of its own between the Sela, Zavost and Darev, and Darev
keeps the far east to the Krasovan line.

The Kesla rises on the Karsen plateau, comes down past the Karsen reservoir and
Lestara, crosses the capital basin at Vashtera, and runs south-west across the
Sela to reach the Aster Sea in a marshy delta beside Tavri. Lesser rivers: the
Orvena water from the Anera highlands to the Orvena bay, an eastern river from
the Darev steppe across Kostrel into the Kesla below the capital, and a short
torrent off the southern hills across Kelvet. The only sea is west and
south-west: every other edge of the map is land, pass or frontier. The coast is
warm, commercially useful and difficult for the state to police.

Veldoria lies beyond the northern passes. Krasova is across the eastern border
of Zavost and Darev, where the old Union industrial system and the Zovar energy
line meet. Merova is beyond the southern hills and the south-eastern lowlands.
The western coast is Ardenian in law; its Vetrenka section, from Ostrena's
headland down to the ceasefire line, is not under Vashtera's control in fact.

## Regional placement and adjacency

| Region | Position | Borders inside Ardenia | Political fact |
|---|---|---|---|
| Anera | north-west highlands, inland of Vetrenka | Vashtera, Sela, Vetrenka | poor, devout, armed, weakly governed |
| Karsen | north-central plateau and passes | Anera, Vashtera, Zavost | upper Kesla, garrisons and winter roads |
| Vashtera | central Kesla basin, the middle of the country | Karsen, Zavost, Sela, Orvena | capital and administrative core |
| Zavost | east, under the northern wall | Karsen, Vashtera, Sela, Darev, Kostrel, Krasova | plants, rail and unions |
| Darev | far east, up to the Krasovan line | Zavost, Kostrel, Merova, Krasova | energy, garrisons and exposed frontiers |
| Sela | the central and southern plain, from Kelvet to Kostrel | Vashtera, Zavost, Kostrel, Kelvet, Orvena | land, grain, roads and rural credit |
| Kostrel | the south-east, between the Sela, Zavost and Darev; Rovets | Sela, Zavost, Darev, Merova | orchards, vineyards, irrigation and farm credit |
| Kelvet | the south-western approaches and the Kesla delta | Sela, Orvena | Tavri, customs and legal/illegal trade |
| Orvena | west-central coast and foothills, behind the Orvena bay | Anera, Vashtera, Sela, Kelvet, Vetrenka | loyalist corridor, displaced families and Selvara |
| Vetrenka | the north-western coast under the wall, Ostrena's headland | Anera, Orvena | separatist-held territory behind the ceasefire line |

Only Vetrenka, Orvena and Kelvet touch the sea. As drawn, Anera also meets
Karsen and Orvena and does not reach the Sela; the map's eighteen internal
borders are pinned by `godot/tests/map/test_map_baker.gd`.

The ceasefire line is **inside** Ardenia's recognised border. It is never to
be rendered as an international boundary or as a normal provincial border.

## Strategic features

- **Kesla corridor:** Karsen headwaters → Lestara → Vashtera → along the Sela →
  Tavri. It is the country's natural administrative and transport spine.
- **Ports:** Tavri at the Kesla delta, and Ostrena behind the ceasefire line.
- **Fortresses:** the Karvel pass fort on the plateau, the monastery walls by
  Kavor, the Meradin frontier citadel, and the old sea fort on Ostrena's headland.
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
- The ten regional ids in `geography.py` are the stable identifiers for the
  regional simulation. Map coordinates are presentation data only.
