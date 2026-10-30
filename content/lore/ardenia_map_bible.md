# Ardenia map bible

This is the spatial canon used by the dashboard map. By the owner's decision
the silhouette is a real Caucasus coast-and-mountain country's outline turned
upside down (north to south), with the coast kept on the west, and then given
its own folds, capes and bays; the names, regions and political geography are
original. No real place name is used.

## The country at a glance

Ardenia is broad east-to-west and compressed north-to-south, and it is not a
rectangle: it is tallest in the west and narrows toward the east like a wedge.
The west coast runs south from Ostrena's cape under the northern wall, past the
Selvara bay, then swings south-west into a long coastal tail, the Kelvet coast,
which ends in a cape of its own. The northern frontier is a broken mountain
wall that protects little and separates more; the Karsen plateau stands out of
it as one high salient. The southern frontier follows a lower southern range,
never snow-capped, that runs from the end of the tail along the Sela's southern
edge and dies out into the dry eastern steppe of Darev. The eastern frontier is
the short, straight Krasovan survey line.

The Kesla rises on the Karsen plateau, comes down past the Karsen reservoir and
Lestara, crosses the capital basin at Vashtera, and runs south-west between
Orvena and the Sela to reach the Aster Sea in a marshy delta beside Tavri.
Lesser rivers fall the same way: the Orvena water from the Anera highlands to
the Selvara bay, an eastern river from the Darev hills into the Kesla below the
capital, and a short torrent off the southern hills across the tail. Lakes sit
on the Karsen plateau, behind the Selvara bay as a coastal lagoon, under the
Sela hills, in the tail's hills and on the Darev steppe. The only sea is west
and south-west: every other edge of the map is land, pass or frontier. The
coast is warm, commercially useful and difficult for the state to police.

Veldoria lies beyond the northern passes. Krasova is across the eastern border
of Zavost and Darev, where the old Union industrial system and the Zovar energy
line meet. Merova is beyond the southern hills and the south-eastern lowlands.
The western coast is Ardenian in law; its Vetrenka section, the north-west
corner between Ostrena's cape and the ceasefire line, is not under Vashtera's
control in fact.

## Regional placement and adjacency

| Region | Position | Borders inside Ardenia | Political fact |
|---|---|---|---|
| Anera | north-west highlands, inland of Vetrenka | Vashtera, Sela, Vetrenka | poor, devout, armed, weakly governed |
| Karsen | north-central plateau and passes | Anera, Vashtera, Zavost | upper Kesla, garrisons and winter roads |
| Vashtera | central Kesla basin, west of centre | Karsen, Zavost, Sela, Orvena | capital and administrative core |
| Zavost | east, under the northern wall | Karsen, Vashtera, Sela, Darev, Krasova | plants, rail and unions |
| Darev | far east: the narrow end of the wedge and its steppe | Zavost, Sela, Merova, Krasova | energy, garrisons and exposed frontiers |
| Sela | the southern plain beneath the southern hills, from the tail to Darev | Vashtera, Zavost, Darev, Kelvet, Orvena | land, grain, roads and rural credit |
| Kelvet | the south-western coastal tail | Sela, Orvena | Tavri, customs and legal/illegal trade |
| Orvena | west-central coast and foothills, behind the Selvara bay | Anera, Vashtera, Sela, Kelvet, Vetrenka | loyalist corridor, displaced families and Selvara |
| Vetrenka | north-western coast, Ostrena's cape | Anera, Orvena | separatist-held territory behind the ceasefire line |

Only Vetrenka, Orvena and Kelvet touch the sea. As drawn, Anera also meets
Karsen and Orvena and does not reach the Sela; the map's sixteen internal
borders are pinned by `godot/tests/map/test_map_baker.gd`.

The ceasefire line is **inside** Ardenia's recognised border. It is never to
be rendered as an international boundary or as a normal provincial border.

## Strategic features

- **Kesla corridor:** Karsen headwaters → Lestara → Vashtera → along the Sela →
  Tavri. It is the country's natural administrative and transport spine.
- **Ports:** Tavri at the Kesla delta, Selvara on its bay, and Ostrena behind
  the ceasefire line.
- **Fortresses:** the Karvel pass fort on the plateau, the monastery walls by
  Kavor, the Meradin frontier citadel, and the old sea fort on the tail's cape.
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
