-- Migration: Replace sample discoveries with curated set of 22
-- Previous set had 7 discoveries (mostly Venice/Budapest).
-- New set has 22 with stronger visual variety, openings, and geographic spread.
--
-- Storage paths use samples/{display_order}.jpg and samples/{display_order}.mp3
-- Images and voiceovers must be uploaded manually to the storage buckets:
--   - discovery_images/samples/{n}.jpg
--   - voiceovers/samples/{n}.mp3
--
-- Grid layout (2 columns):
--   Row 1:  The Last Senate              | House of the Black Heads
--   Row 2:  Inferno in the Palace        | The Empress's Pink Stone
--   Row 3:  The Doge's Giant Ego         | Accidental Sticky Notes
--   Row 4:  Feast in the House of Levi   | Ghetto Heroes Monument
--   Row 5:  The Winged Hussars            | The Merchant's Moral Map
--   Row 6:  The Arm of a Saint           | Trakai's Diverse Streets
--   Row 7:  Sobieski at Vienna           | Polyxena Sarcophagus
--   Row 8:  Palace of Culture            | The Price of Fire
--   Row 9:  A Map to the Afterlife       | Ornate Wheellock
--   Row 10: The Wood Inlays of Frari     | The Rebel Monk Methodius
--   Row 11: Rundāle Palace               | Stoves of Rundāle

-- =============================================================================
-- 1. DELETE EXISTING SAMPLES
-- =============================================================================

DELETE FROM public.sample_discoveries;

-- =============================================================================
-- 2. INSERT NEW SAMPLES
-- =============================================================================

INSERT INTO public.sample_discoveries
    (id, title, short_description, description, image_path, voiceover_path, display_order)
VALUES

-- -------------------------------------------------------------------------
-- Row 1, Left: The Last Senate (dev ID 265)
-- -------------------------------------------------------------------------
(1,
 'The Last Senate',
 'Witness the final moments of a thousand-year republic as these scarlet-clad leaders descend into history.',
 '## The end of a thousand years

In 1797, a government that lasted eleven centuries vanished in a single afternoon. These men are the final members of the Venetian Senate. Earlier today, you saw the grand tomb of a Doge at the Frari church. That monument honored a system at its peak. This painting captures its total collapse. Napoleon Bonaparte had reached the edge of the lagoon and demanded the end of the Republic''s ancient constitution. The Great Council voted to dissolve itself rather than face a bloody siege. They abandoned their sovereignty to avoid total destruction.

## The weight of scarlet silk

The scarlet robes served as the uniform of the Venetian elite. This specific shade of red was reserved for the highest magistrates. Look at the heavy brocade pattern woven into the silk of the central figure. This fabric was meant to make a man look imposing and permanent. On this day, the silk hangs like a heavy weight. It marks these men as remnants of an old world in a new, revolutionary era. The man in the foreground stares forward with a grim, hollow expression. He is walking out of a world that no longer exists.

## Steps into the shadows

The stone steps of the Giants'' Staircase feel cold and unforgiving. Usually, these stairs served as the stage for the coronation of a new Doge. Now, they function as the exit ramp for an entire civilization. Imagine the heavy silence in the courtyard during this final descent. The only sound is the rhythmic clicking of leather shoes against the marble. Above them, the massive statues of Mars and Neptune tower over the scene. The artist includes the base of these giants to show how small the men have become. Venice''s former glory stands frozen in stone while the living Republic walks away into the dark.',
 'samples/1.jpg',
 'samples/1.mp3',
 1),

-- -------------------------------------------------------------------------
-- Row 1, Right: House of the Black Heads (dev ID 322)
-- -------------------------------------------------------------------------
(2,
 'House of the Black Heads',
 'A 14th-century guild hall for bachelor merchants rebuilt in Riga after its destruction in 1941.',
 '## The club for bachelor merchants
Young, unmarried merchants formed an exclusive brotherhood named after a dark-skinned African saint. This building is the House of the Black Heads. It was the social heart of Riga for centuries. The members were mostly foreign bachelors who stayed here while trading goods. They were the ultimate adventurers of the medieval Baltic world. They chose Saint Maurice as their patron. You can still see his image on the blue and gold crests today.

## Rules of the brotherhood
Membership in this elite guild came with strict requirements. Every man had to remain a bachelor to keep his seat at the table. Once a merchant married, he had to leave the brotherhood forever. They essentially controlled the flow of wealth coming into the port from the Daugava River. These men guarded the city walls during war and organized the city''s most lavish feasts. Their influence reached into every corner of Baltic trade.

## A masterwork of reconstruction
The ornate brickwork and gold details are actually much newer than they look. German bombs reduced the original 14th-century hall to rubble in 1941. For decades, the square sat empty under Soviet rule. Locals finally rebuilt the entire structure in the late 1990s using original blueprints. Stone by stone, craftsmen matched the carvings to photographs taken before the war. They even recreated the astronomical clock that tracks the phases of the moon.

## Signs of status and wealth
Look closely at the tall gables reaching toward the sky. Sculptures of Neptune and Mercury guard the facade. These figures signaled to every visitor that Riga was a city of the sea and commerce. The bright red bricks and white stone trim create a style known as Dutch Renaissance. Even the cobblestones in the square follow patterns that once directed carts toward the city gates. The Latin inscriptions on the walls promise that the house will remain for as long as the city exists.',
 'samples/2.jpg',
 'samples/2.mp3',
 2),

-- -------------------------------------------------------------------------
-- Row 2, Left: Inferno in the Palace (dev ID 177)
-- -------------------------------------------------------------------------
(3,
 'Inferno in the Palace',
 'Step into a nightmare of fire and demons in this 16th-century vision of eternal punishment.',
 '## A warning for the powerful
This nightmare vision of the afterlife hung in the most secretive room in Venice. Members of the Council of Ten stared at these flames while deciding who lived and died. These men served as the supreme judges of the Venetian Republic. They handled sensitive cases of high treason and political espionage. The three leaders who met in this specific room were changed every month to prevent corruption. This painting acted as a grim mirror for these powerful men. If they failed in their duty, they believed this chaos awaited them too.

## The weight of Venetian justice
The painting belongs to the tradition of Hieronymus Bosch, a master of surreal moral lessons. In the 1500s, the world felt unstable and full of hidden traps. This art captured the belief that every action carried an eternal consequence. People believed that life was a constant struggle between virtue and damnation. Justice in Venice was a divine responsibility rather than a simple legal matter. The judges used this image to keep themselves humble and focused on the truth.

## A landscape of mechanical monsters
Notice the bizarre machinery and hybrid beasts scattered across the dark landscape. Tiny demons with bird skulls and insect legs push sinners into a giant red vat. A massive, hollowed-out egg on the left serves as a tavern for the damned. You might spot a long knife with ears or a creature with a trumpet for a nose. These strange objects turn the act of punishment into a detailed, mechanical process. The artist wanted to show that sin leads to a world where nothing is natural.

## The suffocating glow of the void
A heavy, dark orb hangs over the entire scene like a dying sun. It casts a sickly light over the crumbling towers and burning horizons. Tiny sparks of fire drift through the air like falling stars. The atmosphere feels thick with soot and the imagined smell of sulfur. It is a landscape of noise and heat where the sky itself has turned to ash. You can almost feel the stifling weight of the smoke rising from the burning ruins. There is no air left to breathe in this eternal basement of the universe.',
 'samples/3.jpg',
 'samples/3.mp3',
 3),

-- -------------------------------------------------------------------------
-- Row 2, Right: The Empress's Pink Stone (dev ID 296)
-- -------------------------------------------------------------------------
(4,
 'The Empress''s Pink Stone',
 'These tourmaline crystals from California were once shipped by the ton to the Imperial Court in China.',
 '## The Empress and the pink stone

A single woman in Beijing nearly emptied the mines of Southern California. The Dowager Empress Cixi was so obsessed with pink tourmaline that she bought tons of it. You can see pieces from the Himalaya Mine and Mesa Grande on these shelves. Between 1902 and 1911, miners in San Diego County focused almost entirely on her orders.

Miners packed the crystals into wooden crates and sent them across the Pacific Ocean. Carvers in the Forbidden City turned the raw stones into snuff bottles, buttons, and jewelry. When the Chinese monarchy fell in 1912, the California tourmaline market collapsed overnight. Thousands of miners lost their jobs because their best customer was gone.

## A global treasure hunt

The labels beneath these stones reveal a world map of discovery and trade. You can see deep red pieces from the Soviet Union and pastel pinks from Afghanistan. The blue stones on the right are a rare variety called indicolite. In the 1700s, Dutch traders brought these colorful crystals back from Sri Lanka.

They noticed the stones could attract hot ashes from their tobacco pipes. They called them "ash-pullers." Scientists eventually realized the stones develop an electric charge when heated or squeezed. This strange property made them popular with both jewelers and early physicists. These specific samples belong to a collection that has been gathered over centuries.

## The complex recipe of color

Crystals like these are the chemical garbage cans of the mineral world. They soak up every leftover element in the cooling magma as they grow. This results in the vivid greens, deep blues, and candy pinks before you. Iron creates the dark greens, while manganese produces the bright pinks.

Notice how the light catches the long, straight grooves running down the sides. These are called striations. They act like tiny gutters along the length of the crystal. If you could touch them, they would feel like the strings of a harp. Many of these pieces are still attached to their original white quartz or gray granite base. This shows exactly how they looked when a miner first cracked open a mountain.',
 'samples/4.jpg',
 'samples/4.mp3',
 4),

-- -------------------------------------------------------------------------
-- Row 3, Left: The Doge's Giant Ego (dev ID 174)
-- -------------------------------------------------------------------------
(5,
 'The Doge''s Giant Ego',
 'Discover the most arrogant tomb in Venice where black and white marble tells a story of power and death.',
 '## A monument built on massive ego

Giovanni Pesaro spent a fortune to ensure no one would ever forget his name. He was one of the wealthiest men in Venice but he was not well liked. He left twelve thousand gold ducats in his will specifically to build this giant tomb. He even chose the location next to the side entrance of this church. He knew every person entering the building would have to look up at him.

## The man who refused to be forgotten

Pesaro had a reputation for being arrogant and difficult during his life. He served as the leader of Venice for only one year before he died. Despite his short reign he wanted the most theatrical monument in the city. The central figure shows him seated in his robes and a tall hat. He looks down at visitors as if he is still giving orders from a throne. His family fought the church for years to keep this much space for one man.

## Giants carved from black stone

Look at the four massive figures standing at the very bottom. These are known as telamones. They appear to be struggling under the weight of the entire upper structure. The artist used contrasting stone to make them stand out. Their bodies are carved from dark black marble while their torn clothing is bright white. This was a deliberate choice to show the Doge''s power over distant lands and people.

## Skeletons hiding in the shadows

If you look closely at the inscriptions you will see something macabre. Two bronze skeletons stand in the niches holding up the marble scrolls. They are tiny compared to the giants but they carry a sharp message. One skeleton holds an hourglass to show that time has run out. Even with all his gold and stone Pesaro could not escape the same end as everyone else.',
 'samples/5.jpg',
 'samples/5.mp3',
 5),

-- -------------------------------------------------------------------------
-- Row 3, Right: Accidental Sticky Notes (dev ID 219)
-- -------------------------------------------------------------------------
(6,
 'Accidental Sticky Notes',
 'Discover how a failed super-glue and a choir singer''s frustration created the world''s most famous yellow pad.',
 '## The invention of a weak glue

In 1968, a scientist named Spencer Silver was trying to invent a super-strong adhesive for aircraft. He failed completely. Instead of a permanent bond, he created a light adhesive. It stuck to surfaces but could be peeled away easily without leaving a mark. For five years, this low-tack adhesive was a solution looking for a problem. Silver spent his time at 3M giving seminars. He tried to convince colleagues that his weak glue was actually a breakthrough.

## A choir singer''s solution

The breakthrough finally arrived in 1974 because of a frustrated choir singer named Art Fry. Fry kept losing his place in his hymnal because his paper bookmarks constantly fell out. He remembered Silver''s light adhesive and applied it to the back of small paper scraps. He quickly realized he could write notes and stick them directly onto the pages. The notes stayed put during the service but could be removed later without tearing the thin paper.

## The yellow paper accident

You might wonder why the most iconic version of this pad is canary yellow. This choice was a total accident of geography and inventory. The lab next door to the development team only had yellow scrap paper available at the time. They used it for all their early prototypes and the color became a massive success with testers. It turned out that bright yellow was the perfect shade to grab attention on a cluttered wooden desk.

## The science of the stick

If you peel a sheet off, you can feel the slight resistance of the adhesive strip. The secret is not a flat layer of glue. The surface is actually covered in tiny, microscopic bubbles called microspheres. These spheres are strong enough to hold the paper''s weight. They let go easily when you pull at an angle. They do not flatten out or soak into the paper. This design allows you to restick the same note many times. It only loses its grip after dozens of uses.',
 'samples/6.jpg',
 'samples/6.mp3',
 6),

-- -------------------------------------------------------------------------
-- Row 4, Left: Feast in the House of Levi (prod ID 1618)
-- -------------------------------------------------------------------------
(7,
 'Feast in the House of Levi',
 'A massive 16th-century banquet that was once too scandalous for the Church.',
 '## A banquet for the eyes

You are standing before one of the largest oil paintings in the world. This massive canvas by Paolo Veronese is nearly thirteen meters wide. It was designed to fill an entire wall of a monastery dining room. The three grand arches act like a window. They create an illusion of deep space. Notice how the painted Corinthian columns match the real architecture of a grand Venetian palace. The perspective is so perfect it feels like you could step onto the checkered floor.

## The craft of Venetian luxury

Veronese was a master of material and color. Look closely at the figures dressed in contemporary 16th-century fashion. The man on the far right wears a shimmering striped tunic. You can almost feel the weight of the heavy silk. The deep reds and vibrant blues were created using the most expensive pigments available. Ground-up lapis lazuli gives the sky its intense depth. Even the dog sitting in the foreground has a realistic, wiry coat. These details were meant to celebrate the immense wealth and craft of Venice. Every silver platter and glass carafe catches the light as if it were real.

## A title to save a life

This painting holds a hidden story of survival. It was originally commissioned as a depiction of the Last Supper. However, the Catholic Church was in the middle of a strict religious crackdown. In 1573, the Inquisition summoned Veronese to explain his work. They were furious that he included "buffoons, drunkards, and Germans" in a holy scene. They even hated the dog. To them, these extras were a sign of disrespect.

Veronese faced a dangerous choice. He could repaint the masterpiece or face a heresy trial. Instead, he made a clever move. He simply changed the name of the painting. By calling it the "Feast in the House of Levi," he referenced a different biblical party. This story allowed for a rowdy crowd. The name change satisfied the inquisitors and saved his life. The painting remained exactly as he intended.',
 'samples/7.jpg',
 'samples/7.mp3',
 7),

-- -------------------------------------------------------------------------
-- Row 4, Right: Ghetto Heroes Monument (dev ID 316)
-- -------------------------------------------------------------------------
(8,
 'Ghetto Heroes Monument',
 'This monument in Warsaw marks the 1943 uprising with stone originally destined for Hitler''s victory.',
 '## Hitler''s stone of defeat

The stone used to build this monument was originally ordered by Adolf Hitler for a victory arch. In 1942, the Nazis imported this dark Swedish stone to Berlin to celebrate their expected victory. Instead, after the war, the blocks traveled to Warsaw to honor the people who resisted them. This monument stands in the heart of what was once the Warsaw Ghetto. It commemorates the thousands of Jewish people who fought and died during the 1943 uprising.

## A choice to fight back

By April 1943, the Nazis had already deported most of the ghetto residents to death camps. The few thousand people remaining knew that their own deaths were imminent. They chose to fight for human dignity rather than a military victory. For nearly a month, they held off well-armed soldiers using handguns and homemade firebombs. This was the first major urban revolt against Nazi occupation in Europe. It shifted the idea of resistance from passive survival to active combat.

## Sculpting the struggle

The bronze figures in the center show the fighters as heroic and muscular. Nathan Rapoport, the sculptor, wanted to capture the intensity of their final stand. Notice the central figure of Mordechai Anielewicz, the young leader of the uprising. He holds a grenade in one hand and looks out with a determined expression. Behind him, men and women emerge from the flames of the burning ghetto. The sculpture shows the human cost of choosing to resist an overwhelming force.

## The hidden flip side

Walk around to the back of the massive stone wall to see a different scene. While the front celebrates the warriors, the reverse side honors the millions who suffered in silence. It shows a simple stone relief of people being led to their deaths. They lean forward, exhausted and burdened. This contrast forces you to hold two ideas at once. It shows the courage of the few and the suffering of the many. The monument balances the fire of the revolt with the cold reality of the tragedy.',
 'samples/8.jpg',
 'samples/8.mp3',
 8),

-- -------------------------------------------------------------------------
-- Row 5, Left: The Winged Hussars (dev ID 183)
-- -------------------------------------------------------------------------
(9,
 'The Winged Hussars',
 'Meet the elite shock troops of the Polish-Lithuanian Commonwealth, famous for their leopard skins and terrifying feathered wings.',
 '## The invincible cavalry

For over a century, these riders were considered the most dangerous men on a European battlefield. They were the Polish Winged Hussars. This elite group of noblemen specialized in the heavy cavalry charge. They were famous for winning battles against much larger armies. Joining this unit was a birthright for the wealthiest families in the Polish-Lithuanian Commonwealth. Each hussar was expected to provide his own horses and equipment. This meant they spent fortunes on the finest steel and the most striking decorations.

## A skin of status

The leopard skin draped over the steel breastplate served a specific social purpose. Only the most successful officers wore the pelts of exotic predators like leopards or tigers. This was a uniform designed to signal wealth and power before a single sword was drawn. The steel beneath the fur is thin and light compared to earlier medieval suits. It gave the rider enough protection to survive a charge while remaining fast enough to maneuver. These men were the celebrities of their day. They wore their armor at weddings and royal funerals to remind everyone of their rank.

## The rattle and the roar

The most famous feature of this armor is the pair of feathered wings arching over the shoulders. As a line of hundreds of hussars galloped at full speed, these wings created a terrifying physical experience. The air rushing through the eagle feathers made a high-pitched whistling sound. The wooden frames also rattled against the metal plate. This created a rhythmic clatter that echoed across the field. This combined noise made it sound like a much larger force was attacking. It frightened enemy horses and confused the soldiers trying to hold the line. You can almost feel the vibration and wind that would follow such a massive charge.',
 'samples/9.jpg',
 'samples/9.mp3',
 9),

-- -------------------------------------------------------------------------
-- Row 5, Right: The Merchant's Moral Map (dev ID 134)
-- -------------------------------------------------------------------------
(10,
 'The Merchant''s Moral Map',
 'Explore a 16th-century vision of global trade where profit meets morality in the port of Antwerp.',
 '## The balance of debt and credit

Look at the large scales hanging near the top of the image. On one side you see the word for debtor. On the other side is the word for creditor. This complex print serves as a moral map for sixteenth-century businessmen. It explores the delicate balance between profit and ethics. In this era, massive wealth was often viewed with suspicion. This artwork argues that a good merchant provides a vital service to society. The scales remind the viewer that every gain comes with a responsibility to others.

## The heart of global commerce

In the center of the frame, you can see a wide panoramic view. This is the city of Antwerp. During the 1500s, this was the busiest port in the world. Notice the forest of ship masts filling the harbor. Goods from the Americas and Asia flowed through these waters. The print captures the sheer energy of this new global economy. You can see wagons being loaded and clerks counting coins in the foreground. It celebrates the city as a massive engine of trade and connection.

## Life inside the merchant''s house

The bottom sections of the print zoom into the private world of the office. Merchants and their assistants sit at long tables covered in ledgers. They are surrounded by the tools of their trade like inkwells and wax seals. These scenes illustrate the daily grind of the commercial world. It was not all high-seas adventure. Much of the work happened in quiet rooms filled with paperwork. Notice the serious expressions on their faces. They are managing the risks of a world that was rapidly expanding.

## A tapestry of wood and ink

This is not a single small stamp. It is a giant woodcut print made from several different blocks joined together. If you look closely, you can see the faint vertical lines where the paper sheets meet. This was a high-tech object for its time. A wealthy merchant would display this in his office like a modern computer dashboard. It contains a calendar, a list of coats of arms, and moral advice. The level of detail in the tiny carvings is incredible. Every face and barrel tells a story of the material world.',
 'samples/10.jpg',
 'samples/10.mp3',
 10),

-- -------------------------------------------------------------------------
-- Row 6, Left: The Arm of a Saint (dev ID 309)
-- -------------------------------------------------------------------------
(11,
 'The Arm of a Saint',
 'A 16th-century silver reliquary containing a bone fragment of Saint Casimir, the patron of Lithuania.',
 '## A physical link to the divine

A piece of human bone rests inside this silver hand. This is an arm reliquary from the Vilnius Cathedral Treasury. In the 1500s, people believed these objects held the actual power of the dead. They did not pray to the silver itself. They used the metal hand to focus their requests to the person whose bone was inside. This specific fragment belonged to Saint Casimir. He is the same royal prince whose miracle helped defend the castle you visited earlier today.

## The spiritual capital of a kingdom

Relics were the most valuable assets a medieval city could own. They functioned as a form of spiritual currency. Having the body of a royal saint like Casimir proved that God favored the Grand Duchy of Lithuania. When the nation faced war or plague, priests carried this arm through the streets of Vilnius. They believed the presence of the bone could physically push back misfortune. It gave the people a shared identity and a sense of heavenly protection.

## A window into the sacred

Look closely at the small rectangular window in the center of the forearm. This is a crystal pane designed to reveal the actual bone fragment tucked inside. Gold filigree and hammered silver wrap the rest of the arm like a sleeve of expensive fabric. Master goldsmiths shaped the metal to look like a hand frozen in a gesture of blessing. They used these precious materials to signal that the contents were more valuable than anything else on earth. The gold caught the flickering candlelight of the cathedral to make the saint appear radiant in the gloom.',
 'samples/11.jpg',
 'samples/11.mp3',
 11),

-- -------------------------------------------------------------------------
-- Row 6, Right: Trakai's Diverse Streets (dev ID 229)
-- -------------------------------------------------------------------------
(12,
 'Trakai''s Diverse Streets',
 'Discover how Grand Duke Vytautas transformed Trakai into a crossroads of world religions and cultures.',
 '## The bodyguards of the Grand Duke
In 1397, Grand Duke Vytautas returned from the Black Sea with nearly four hundred families. These people were Karaimes and Tatars. He did not bring them to Trakai as captives. He brought them to serve as his most trusted bodyguards. They were famous for their loyalty and military skill. Vytautas granted them land on the thin peninsula between the lakes. This map shows the heart of that settlement. You can see the label for the Totoriškių Lake. That name honors the Tatar community that has lived here for six centuries.

## A town of three windows
The people on this map shaped the very look of the town. If you walk down the main streets today, look for the wooden houses. Most face the street with exactly three windows. Local legend says each window has a specific purpose. One window is for God. The second is for the Grand Duke who invited them here. The third is for the family living inside. These families maintained their Turkic languages and unique customs far from their original homes. They became the keepers of the castle. They worked as translators, farmers, and craftsmen.

## Faiths on a single street
This map shows a rare level of religious harmony for the Middle Ages. You can see the crescent moon marking the mosque, or mečetė. Right nearby is the cross of the parish church. For centuries, the calls to prayer and church bells sounded in the same air. The Grand Duchy of Lithuania was a patchwork of different beliefs. Leaders realized that the state was stronger when people practiced their faiths freely. Trakai became a sanctuary where Catholic, Orthodox, and Muslim neighbors lived side by side. It was a practical solution to a complex world. The map you see today preserves that fragile balance of old world identities.',
 'samples/12.jpg',
 'samples/12.mp3',
 12),

-- -------------------------------------------------------------------------
-- Row 7, Left: Sobieski at Vienna (prod ID 1771)
-- -------------------------------------------------------------------------
(13,
 'Sobieski at Vienna',
 'King Jan III Sobieski leads the legendary 1683 charge that broke the Ottoman siege and saved Vienna.',
 '## A collision of empires

This painting captures the exact moment the map of Europe was rewritten. It depicts the Battle of Vienna in September 1683. At the time, the Ottoman Empire had surrounded the city and brought it to the brink of collapse. This was seen as much more than a local conflict. It was an existential clash of ideas between the East and the West. If Vienna fell, the road into the heart of the Holy Roman Empire would be wide open. This battle represented the idea of the "Bulwark of Christendom." It was a rallying cry that brought together soldiers from across the continent to defend a shared identity.

## The king who answered the call

The man commanding your attention on the white horse is King Jan III Sobieski of Poland. He arrived at the eleventh hour with a massive relief force. Sobieski was a brilliant tactician who understood that the siege could only be broken by a single, overwhelming blow. He led the largest cavalry charge in history to shatter the Ottoman lines. Look at his raised saber and the calm authority in his eyes. To his contemporaries, he was a hero of mythic proportions. After the victory, he sent a letter to the Pope. He wrote, "We came, we saw, and God conquered." This humble message masked his role as the architect of the greatest military triumph of the age.

## Camels and cannons in the dust

Now, look past the central figures toward the edges of the fray. On the right, you can see camels moving through the smoke of the Ottoman camp. These animals carried the massive silk tents and supplies of the Grand Vizier''s army. Their presence creates a striking visual contrast with the armored European horses in the foreground. You can also spot the red flags bearing the white crescent moon of the Ottoman forces. These objects and animals tell a story of a global empire that had marched thousands of miles. The painting uses these details to show how two different worlds literally collided on the hills overlooking the city.',
 'samples/13.jpg',
 'samples/13.mp3',
 13),

-- -------------------------------------------------------------------------
-- Row 7, Right: Polyxena Sarcophagus (dev ID 40)
-- -------------------------------------------------------------------------
(14,
 'Polyxena Sarcophagus',
 'A stunning marble tomb from 500 BC that uses Trojan myth to honor a lost noblewoman.',
 '## A myth for the afterlife
This massive marble box is the Polyxena Sarcophagus. It was carved around 500 BC. You are looking at a powerful use of myth to process a real death. Earlier today, you saw a decree found at the site of Troy. This sarcophagus was discovered nearby and uses those same Trojan legends. The people living here used these stories to explain their own place in the world. They saw themselves as the heirs to the heroes of the Iliad.

## The price of a hero
Look closely at the figures on the side. This is the sacrifice of Polyxena. She was the youngest daughter of King Priam of Troy. After the city fell, the ghost of Achilles demanded her life. The carver shows the moment of her death at Achilles'' tomb. This gruesome scene likely mirrored the status of the woman buried inside. She was a high-ranking noblewoman. Her family used the tragedy of a princess to elevate her own funeral.

## Art between two worlds
Notice the style of the figures. This is the late Archaic period. The people are stiff and formal. Their hair is braided in tight patterns. This style reflects a world in transition. At this time, the region was under Persian rule but influenced by Greek art. This sarcophagus is a perfect mix of those two cultures. It shows how art can bridge the gap between different empires. It turned a private burial into a lasting political statement.

## The mark of the intruder
Now look up at the lid. You can see a large, jagged hole. This is the physical evidence of an ancient crime. Grave robbers smashed through the stone centuries ago. They were looking for the jewelry and gold buried with the body. The hole breaks the rhythm of the beautiful carvings. It reminds us that even the most sacred monuments are vulnerable. The marble was meant to be eternal but human greed was stronger.',
 'samples/14.jpg',
 'samples/14.mp3',
 14),

-- -------------------------------------------------------------------------
-- Row 8, Left: Palace of Culture (dev ID 237)
-- -------------------------------------------------------------------------
(15,
 'Palace of Culture',
 'Warsaw''s tallest historic landmark hides stories of Soviet power and rock and roll.',
 '## Stalin''s forty million bricks

Joseph Stalin sent forty million bricks and five thousand Soviet workers to build this skyscraper in 1955. It was officially a gift from the Soviet Union to the people of Poland. At the time, it was the tallest building in the country. It stood as a permanent reminder of Soviet power over the city of Warsaw. Stalin wanted the architecture to look national in form but socialist in content. Architects studied local Renaissance palaces to add traditional Polish carvings to the massive Soviet frame.

## From occupation to landmark

For decades, many residents of Warsaw viewed this building as a symbol of foreign occupation. Some politicians suggested tearing it down after the fall of communism in 1989. However, the tower had become an essential part of the city''s skyline. In 2007, the government designated it as a protected historic monument. Today, it houses theaters, a cinema, and university offices. It has transformed from a political statement into a public living room for the city.

## Rock and roll behind the Iron Curtain

Thousands of people enter the building every day for work and leisure. Children swim in the massive indoor pool while students attend lectures upstairs. In the 1960s, the Rolling Stones even played a legendary concert in the Congress Hall. The crowd went wild as the band brought Western rock music behind the Iron Curtain. It remains a place where the heavy history of the Cold War meets modern Polish life.

## The clocks and the falcons

In the year 2000, four massive clock faces were added to the tower. Each clock is over six meters wide. They are the highest clock faces in Europe. The building also hosts a rare colony of peregrine falcons near the spire. People often gather at the base to watch the tower change color. On many nights, the stone walls glow with vibrant purple or blue lights.

## A view from the thirtieth floor

The terrace on the thirtieth floor offers a unique spatial experience of the capital. To reach it, you ride a high-speed elevator that clears thirty floors in seconds. Once outside, the wind usually picks up as you overlook the rebuilt Old Town. You can see how the entire city grew around this central anchor. Modern glass skyscrapers now surround the square, but they look small from here. The massive scale of the plaza makes the rest of the city feel like a model.',
 'samples/15.jpg',
 'samples/15.mp3',
 15),

-- -------------------------------------------------------------------------
-- Row 8, Right: The Price of Fire (dev ID 125)
-- -------------------------------------------------------------------------
(16,
 'The Price of Fire',
 'Discover why this marble titan was a hero to rebels and thinkers in 19th-century Berlin.',
 '## The hero of the human mind

You are looking at the Greek titan Prometheus. This marble group by Eduard Müller captures a moment of eternal suffering for a grand idea. In ancient myth, Prometheus stole fire from the gods and gave it to humanity. Fire represented more than warmth or light. It was the spark of technology, science, and independent thought. By bringing it to us, he broke the monopoly of the gods. This made him a favorite figure for artists and philosophers in the 1800s. They saw him as the ultimate symbol of human progress and intellectual rebellion.

## A monument to defiance

During the 19th century, German thinkers were obsessed with the idea of the heroic individual. They valued the person who stands up against overwhelming power for the sake of a better world. Prometheus represents the struggle of the mind against rigid authority. The chains around his wrists are the price of his defiance. The eagle pecking at his liver is a reminder of the constant pain that comes with change. The figures at his feet represent the vulnerable humans he chose to protect. This sculpture was intended to remind viewers that great ideas often require great sacrifice.

## A jewel for the National Gallery

Müller carved this entire group from a single massive block of Carrara marble in Rome. It was a technical triumph that took over a decade to complete. When it arrived in Berlin, it was hailed as a masterpiece of the Romantic era. The goal of this style was to match the perfection of ancient Greek art. Artists wanted to use the human form to express deep emotional and moral truths. In this niche, the sculpture acts as a guardian of the museum''s intellectual mission.

## The tension in the stone

If you look closely, you can see how the artist cheated the weight of the stone. Notice the rippling muscles in the titan''s torso as he strains against his bonds. The eagle''s wings look dangerously sharp and light compared to the heavy rock base. There is a sense of violent movement frozen in the silence of the marble. You can almost feel the coldness of the sandstone wall contrasting with the heat of the struggle. It is a scene of raw physical energy trapped forever in a still and silent material.',
 'samples/16.jpg',
 'samples/16.mp3',
 16),

-- -------------------------------------------------------------------------
-- Row 9, Left: A Map to the Afterlife (dev ID 57)
-- -------------------------------------------------------------------------
(17,
 'A Map to the Afterlife',
 'Explore ancient Egyptian spells and the royal quest that brought them to Berlin.',
 '## A legal defense for the soul
You are looking at sections of an ancient Egyptian Book of the Dead. For the Egyptians, death was not just an end but a complex legal trial. To reach paradise, a person had to prove their heart was pure. These scrolls served as a survival manual for that journey. They contained forty-two denials of sin that the deceased had to recite perfectly. By speaking these words, they claimed they had never stolen or lied. This was a system where knowledge of the right spells was just as important as a good life.

## The king''s desert expedition
Earlier today, you met King Frederick William IV outside the Alte Nationalgalerie. He is the reason these fragile scrolls are here in Berlin. In the 1840s, he funded a massive expedition to Egypt led by Karl Richard Lepsius. The team spent three years recording tombs and collecting treasures like these papyri. The king wanted Berlin to compete with the great museums of London and Paris. His passion for the ancient world transformed this island into a global center for history. These scrolls are part of that royal legacy.

## The sun god''s eternal boat
Look at the colorful scroll at the top. You can see various gods overseeing the journey of the deceased. In the bottom scroll, notice the figure in a boat. This represents the sun god, Ra, as he travels through the sky. The Egyptians viewed time as a repeating circle rather than a straight line. Every night the sun died and entered the dangerous underworld. Every morning it was reborn. By placing these images in a tomb, a person hoped to join that same eternal cycle of rebirth.

## Written in red and black
If you look closely at the ink, you will notice two distinct colors. Scribes used black ink for the main text, made from soot mixed with water. Red ink was reserved for titles or the most important instructions. These characters were painted with a frayed reed brush onto strips of papyrus. Papyrus was made by layering the inner pith of river plants and pounding them together. Even after three thousand years, the organic fibers and carbon ink remain incredibly clear. This material was the high technology of the ancient world.',
 'samples/17.jpg',
 'samples/17.mp3',
 17),

-- -------------------------------------------------------------------------
-- Row 9, Right: Ornate Wheellock (dev ID 261)
-- -------------------------------------------------------------------------
(18,
 'Ornate Wheellock',
 'Discover how a master gunsmith turned a deadly weapon into a scientific marvel and a status symbol for kings.',
 '## The science of status

These ornate firearms were designed to demonstrate political power through expensive technology. In the sixteenth century, owning a wheellock carbine was like owning a high-end sports car today. It signaled that the owner was part of a wealthy, tech-literate elite. While common soldiers carried cheaper weapons, these pieces functioned as portable diplomatic statements. The intricate bone and ivory inlays transformed a tool of death into a canvas for art. This shift marked a new era where warfare and high culture became inseparable.

## A revolution in ignition

The mechanism on the side of this barrel represents a massive leap in mechanical engineering. Before this invention, a soldier had to carry a glowing, slow-burning cord to fire his gun. That cord was dangerous around gunpowder and glowed in the dark. This wheellock replaced the flame with a rotating steel wheel and a piece of pyrite. It worked exactly like a modern cigarette lighter. Pulling the trigger released a spring that spun the wheel against the stone. This created a shower of sparks to ignite the powder instantly.

## The mark of a gentleman

These weapons allowed for the rise of the elite cavalry officer. Because a wheellock could be kept loaded and ready, a nobleman could carry it in a holster. It changed the social hierarchy of the battlefield. It gave the individual rider a level of independence that foot soldiers lacked. You are looking at a weapon that likely belonged to a member of the Polish nobility or the royal court. The delicate floral patterns were meant to be admired during a parade or a hunt. They were symbols of a world where even violence was expected to be elegant.

## A heavy spark

If you held this carbine, the first thing you would notice is the surprising weight. The thick steel barrel and dense wood stock make it feel incredibly solid. When fired, the mechanism produced a sharp, metallic grinding sound followed by a cloud of acrid smoke. You would feel the vibration of the heavy spring snapping the wheel into motion. There was a brief delay between the spark and the roar of the explosion. It was a sensory mix of fine craftsmanship and raw, mechanical power.',
 'samples/18.jpg',
 'samples/18.mp3',
 18),

-- -------------------------------------------------------------------------
-- Row 10, Left: The Wood Inlays of Frari (dev ID 307)
-- -------------------------------------------------------------------------
(19,
 'The Wood Inlays of Frari',
 'Marco Cozzi carved these 124 choir stalls in 1468 using hundreds of tiny pieces of colored wood.',
 '## A city built from wood

Marco Cozzi used zero paint to create these intricate cityscapes in 1468. He spent seven years fitting thousands of tiny wood fragments together like a puzzle. These are the choir stalls of the Basilica di Santa Maria Gloriosa dei Frari. Above the cityscapes, relief carvings show religious figures like Mary Magdalene with her long, flowing hair. Cozzi carved every detail by hand into solid blocks of dark walnut.

## The illusion of depth

Notice the tiny black and white floor tiles in the bottom left panel. Cozzi used different species of trees to create every single color you see. Dark walnut forms the deep shadows. Pale willow creates the bright sunlight hitting the walls. This technique is called intarsia. In the 1400s, this mastery of perspective was a cutting-edge artistic technology. It allowed monks to look into an imaginary city while they sat in their real one.

## Spirals and gilded shells

Two twisted columns frame the central panels. Architects call these Solomonic columns. Tradition says the original Temple of Solomon in Jerusalem featured this exact spiraling shape. Carvers used specialized chisels to follow the grain of the wood around the curve. Above the columns, gold leaf covers the carved wooden shells. This gold caught the flickering candlelight during early morning prayers. The contrast between the dark wood and bright gold helped the altar glow in the dim light.

## Voices in the dark

Franciscan monks sat in these seats seven times every single day. They began their first prayers at two in the morning while the rest of Venice slept. The curved wood surrounding each seat projected the sound of the chanting deep into the church. The monks rested their hands on the smooth armrests as they sang in the cold air. You can almost hear the low hum of their voices vibrating through the aged timber. These stalls have held the weight and prayers of thousands of men over five centuries.',
 'samples/19.jpg',
 'samples/19.mp3',
 19),

-- -------------------------------------------------------------------------
-- Row 10, Right: The Rebel Monk Methodius (dev ID 173)
-- -------------------------------------------------------------------------
(20,
 'The Rebel Monk Methodius',
 'Discover the man who survived a dungeon to give the Slavic world its first alphabet.',
 '## A monk in a dark dungeon

Methodius spent two years in a dark dungeon for preaching in a language people actually understood. In the ninth century, powerful bishops believed only Latin, Greek, and Hebrew were holy enough for prayer. Methodius disagreed. He believed that if a person could not understand the words, the message was lost. This mosaic shows him in his bishop''s robes. However, his real power lay in his stubbornness.

## Two brothers on a royal mission

Methodius and his younger brother Cyril were brilliant scholars from Greece. An emperor sent them north into the Great Moravian Empire to educate the tribes living there. They realized immediately that these people had no way to write down their own history. The brothers did something radical. They invented an entirely new alphabet from scratch. This mission reached far beyond religion. It was a massive project of cultural survival.

## Surviving the battle of languages

This invention made the local German bishops furious. They saw Methodius as a threat to their political control over the region. They arrested him and dragged him before a council. They locked him away until the Pope in Rome sent a direct order to release him. Methodius returned to his work immediately. He finished translating almost the entire Bible into the common tongue before he died.

## The invention of the Slavic voice

Look closely at the book clutched in his hand. It holds the Glagolitic alphabet. This is the complex ancestor of the modern Cyrillic script. Before this, these local sounds had no visual form. This script allowed millions of people to read and write in their native tongue. It provided a tool for independence. By giving people an alphabet, Methodius ensured their culture would survive even if empires fell.',
 'samples/20.jpg',
 'samples/20.mp3',
 20),

-- -------------------------------------------------------------------------
-- Row 11, Left: Rundāle Palace (dev ID 298)
-- -------------------------------------------------------------------------
(21,
 'Rundāle Palace',
 'The 18th-century summer home of the Duke of Courland, designed by the architect of the Winter Palace.',
 '## The favorite''s grand ambition

One man''s obsession with Russian power turned this remote Latvian field into a miniature St. Petersburg. This is Rundāle Palace. It was the summer home of Ernst Johann von Biron, the Duke of Courland. Biron was the favorite and lover of the Russian Empress, Anna Ioannovna. He used her immense wealth and influence to transform himself from a minor noble into a ruler. This building was his way of proving he belonged among the elite of Europe.

## Designing for an Empress

The Duke hired Bartolomeo Rastrelli to design every inch of this estate. Rastrelli is the famous architect responsible for the Winter Palace in Russia. He brought the same dramatic Baroque style to this countryside. You can see his signature in the yellow facades and the white stucco decorations. Every window and column follows a strict symmetry. In the 1700s, this order was a message. It told the world that the Duke had total control over his land and his people.

## A life of sudden exile

Politics in the 18th century was a dangerous game. Biron enjoyed this luxury for only a few years before the Empress died. Her successors immediately stripped him of his titles and sent him to exile in Siberia. For over twenty years, these grand halls sat empty and silent. The palace was eventually finished decades later when Biron was finally allowed to return. It remains a testament to how quickly fortune can turn in the shadow of an empire.

## The weight of the stone

Step into the center of the courtyard and listen to the wind. The three wings of the palace wrap around you to block out the surrounding plains. The uneven cobblestones under your feet were designed for horse-drawn carriages, not modern shoes. When the sun hits the yellow walls, the light bounces back with a golden intensity. It feels like standing inside a giant, open-air room. Even today, the scale of the courtyard makes a single person feel very small against the weight of the stone.',
 'samples/21.jpg',
 'samples/21.mp3',
 21),

-- -------------------------------------------------------------------------
-- Row 11, Right: Stoves of Rundāle (dev ID 199)
-- -------------------------------------------------------------------------
(22,
 'Stoves of Rundāle',
 'Discover how this towering ceramic masterpiece kept a massive Latvian palace warm during the freezing winters of the 1700s.',
 '## A tower of blue and white
Nearly eighty hand-painted ceramic tiles cover this massive heating tower from top to bottom. Each tile shows a unique miniature scene of Dutch landscapes or tiny sailing ships. This specific blue and white glaze was the height of fashion in the mid-1700s. It mimics the famous Delftware pottery from the Netherlands. The tiles are arranged in a strict geometric grid that stretches toward the ceiling. They catch the light from the nearby crystal chandeliers and make the heavy masonry look almost delicate.

## Thermal engineering in porcelain
This structure works like a giant battery for heat. A wood fire burned deep inside the thick brick core for several hours. The heavy ceramic tiles absorbed that intense energy and held onto it. Long after the flames died out, the stove slowly released warmth back into the room. In the brutal Latvian winters, this was the only way to keep these high-ceilinged halls livable. The small columns in the middle section are not decorative. They create more surface area for the warm air to circulate and heat the room faster.

## The invisible fire
The Duke and his guests enjoyed this warmth without ever seeing the mess of a fire. Servants stoked the wood and cleared the ash from hidden corridors behind the walls. This system kept smoke and soot away from the fine silk wallpaper and gilded frames. While royalty danced or played cards on this side, workers hauled heavy logs in the dark passages next door. To the people in this room, the heat felt like a silent, invisible miracle. It allowed them to live in luxury while the world outside stayed frozen.',
 'samples/22.jpg',
 'samples/22.mp3',
 22);

-- =============================================================================
-- 3. RESET SEQUENCE
-- =============================================================================

SELECT setval('sample_discoveries_id_seq', (SELECT COALESCE(MAX(id), 0) FROM sample_discoveries));
