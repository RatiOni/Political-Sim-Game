"""Ardenia's political timeline, from the Terzhan Crown to March 1993."""

_CAPITAL = "Vashtera"
_UNION_NAME = "the Kolvenian Union"
_UNION_DOCTRINE = "Dravism"
_SEPARATIST_REGION = "Vetrenka"


# (period, title, body) — rendered top to bottom by the Codex. The final
# eleven entries are the original timeline verbatim; the first four supply
# the pre-1918 floor Ardenians assume when discussing the republic.
TIMELINE = [
    ("c. 1090–1461", "The Terzhan Crown",
     "A medieval Ardenian kingdom that reached its height under Queen Sevra "
     "in the 1340s, when it ran from the northern mountains to the whole of "
     "the Kelvet coast — including Vetrenka. That last fact is the historical "
     "claim every Ardenian schoolchild learns and every Vetreni schoolchild "
     "learns to dispute. Conquest ended the Crown in 1461."),

    ("1461–1878", "Four centuries of partition",
     "The Sarine Porte took the south and coast; the Verdan Empire later took "
     "the north and plain. Tavri's minarets, Anera's monasteries and Ardenia's "
     "two legal traditions are the inheritance. Vetrenka spent much of the "
     "period as a self-governing port under Sarine suzerainty, which is its "
     "answer to the claim of the Terzhan Crown."),

    ("1860s–1890s", "The Lamplight",
     "Grammarians and poets standardised the Verzhan script and published the "
     "first Ardenian-language newspaper in 1867. They made modern Ardenian "
     "nationhood in print before it existed in law. Their movement was civic "
     "and literary rather than ethnic, a distinction the Liberal Democrats "
     "stress and the National Conservatives do not."),

    ("1878–1918", "1878–1918",
     "After a war neither Ardenians nor Vetreni were consulted about, both "
     "imperial holdings passed to a single crown. Forty years brought a railway, "
     "a bureaucracy and an imperial administration, while the nationalist "
     "movement moved from reading societies into street politics."),

    ("1918–1921", "The First Republic",
     "When the old imperial order came apart at the end of the 1910s, Ardenia "
     "declared itself a republic under the Ardenian Compact, with Anton Radic "
     "as president. It was poor, agrarian, barely armed, recognised by "
     "everyone and secured by no one. It lasted three years."),

    ("February 1921", "The February Intervention",
     f"{_UNION_NAME.capitalize()} crossed the border, invited in — by its own "
     "account — by a workers' rising in the eastern industrial towns that "
     "nobody in those towns remembers happening. Resistance collapsed in "
     "weeks. The Compact's ministers fled into exile and most were never "
     "heard from again. Every independence movement since has invoked "
     "February 1921, and every one of them has meant it."),

    ("1921–1989", "Union rule",
     f"Sixty-eight years as a constituent republic, governed by the Ardenian "
     f"Dravist Party under the doctrine {_UNION_DOCTRINE} — Aurel Draven's "
     "theory of collectivised production and single-party stewardship. The "
     "period brought industry, literacy and electrification, and it brought "
     "collectivisation, purges in the thirties and again after the war, and "
     "a steady pressure on the Ardenian language that never quite succeeded "
     "and never stopped being resented. By the 1980s the centre was losing "
     "its grip and the local party was quietly splitting between hardliners "
     "and reformers who could see which way the wind blew."),

    ("Spring 1989", "Kestrel Square",
     f"A pro-independence demonstration filled Kestrel Square in {_CAPITAL}. "
     "Troops were ordered in and dozens were killed. The funerals became the "
     "largest demonstrations the country had ever seen, and the question "
     "stopped being whether Ardenia would leave the Union and became when. "
     "Every party in the chamber today traces some of its founding membership "
     "to that square."),

    ("1990–1991", "The Awakening",
     "Mass resignations from the Dravist Party, the legalisation of the "
     "opposition, a landslide referendum, and a declaration of independence "
     "delivered while the Union was busy dying. The movement had one voice: "
     "Dorin Vasca, a dissident writer who had been in and out of custody for "
     "a decade and came out of Kestrel Square as its undisputed leader."),

    ("1991", "The Vasca Presidency",
     "Vasca won the first free election in a landslide and spent the next "
     "several months proving that a man who has been persecuted is not "
     "thereby immune to persecuting others. Journalists were harassed. "
     "Allies inside his own movement were purged as traitors. By December "
     "most of the people who had put him in office wanted him out of it."),

    ("Dec 1991 – Jan 1992", "The Turn of the Year",
     f"Six weeks of street fighting in {_CAPITAL} between forces loyal to "
     "Vasca and an alliance of convenience: the National Guard under General "
     "Aurel Doncic, and the Falcons, an irregular paramilitary confederation "
     "run by the black-marketeer Bogdan Yeska. Vasca was driven from the "
     "capital in January and went west to his home region with a hard core "
     "of loyalists. He has not been seen since, and he has not been "
     "confirmed dead."),

    ("1992", "The Baran State Council",
     "Doncic and Yeska trusted each other exactly as far as they had to, "
     "which is why the chairmanship went to Cyrus Baran — a former Union-era "
     "trade envoy with no army, no militia and enough foreign credibility to "
     "make the arrangement look like a government. He inherited "
     "hyperinflation, empty shelves and rolling blackouts, and he kept the "
     "state from coming apart, which at the time was the whole of the job."),

    ("Spring–autumn 1992", "The Vetrenka War",
     f"{_SEPARATIST_REGION}, a coastal region with its own history of "
     "autonomy and no great attachment to Ardenia, rose under the Vetrenka "
     "Free Front — encouraged, armed and then disowned by neighbours who "
     "preferred an Ardenia too busy to look outward. The war was short and "
     "one-sided. By autumn Ardenian forces were out of the region entirely, "
     "and the Council, already fighting Vasca's remnant in the west, took a "
     "ceasefire it could not enforce along a border it does not recognise. "
     f"{_SEPARATIST_REGION} is not a closed question. It is the open wound."),

    ("Late 1992 – early 1993", "The Reckoning",
     "Baran did not stand. A State Council chairman running for permanent "
     "power would have confirmed everything the coup was accused of, and he "
     "knew it. He put his credibility behind the Liberal Democrats instead "
     "and let the country decide. The election Ardenians call the Reckoning "
     "returned a fragmented chamber: Liberal Democrats first, National "
     "Conservatives close behind, Social Democrats holding the balance, and "
     "the Agrarian Union and Workers' Front on the margins. Nobody won the "
     "right to govern alone; the coalition bargain decides who takes office."),

    ("March 1993", "Now",
     "A government takes office this month. The currency is unstable, every "
     "viable coalition is a marriage of necessity, a fifth of the country answers to "
     "someone else, and somewhere to the west a man who was once the most "
     "popular figure in Ardenia is still alive. Good luck."),
]
