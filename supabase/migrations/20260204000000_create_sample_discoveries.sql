-- Migration: Create sample_discoveries table for pre-onboarding
-- This table stores curated discoveries shown to users before sign-up

-- =============================================================================
-- 1. CREATE TABLE
-- =============================================================================

CREATE TABLE public.sample_discoveries (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    short_description TEXT,
    description TEXT,
    image_path TEXT NOT NULL,           -- Path in storage: samples/1.jpg
    voiceover_path TEXT,                -- Path in storage: samples/1.mp3
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.sample_discoveries IS 'Curated discoveries shown during pre-onboarding before user sign-up';
COMMENT ON COLUMN public.sample_discoveries.image_path IS 'Relative path in discovery_images bucket, e.g., samples/1.jpg';
COMMENT ON COLUMN public.sample_discoveries.voiceover_path IS 'Relative path in voiceovers bucket, e.g., samples/1.mp3';

-- =============================================================================
-- 2. ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE public.sample_discoveries ENABLE ROW LEVEL SECURITY;

-- Public read access - no authentication required
CREATE POLICY "Anyone can read sample discoveries"
    ON public.sample_discoveries
    FOR SELECT
    USING (true);

-- =============================================================================
-- 3. INDEXES
-- =============================================================================

CREATE INDEX idx_sample_discoveries_display_order
    ON public.sample_discoveries(display_order);

-- =============================================================================
-- 4. RPC FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION get_sample_discoveries()
RETURNS TABLE (
    id INT,
    title TEXT,
    short_description TEXT,
    description TEXT,
    image_path TEXT,
    voiceover_path TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    SELECT
        id,
        title,
        short_description,
        description,
        image_path,
        voiceover_path,
        created_at
    FROM sample_discoveries
    ORDER BY display_order ASC;
$$;

COMMENT ON FUNCTION get_sample_discoveries() IS 'Returns all sample discoveries ordered by display_order for pre-onboarding';

-- =============================================================================
-- 5. SEED DATA
-- =============================================================================

INSERT INTO public.sample_discoveries
    (id, title, short_description, description, image_path, voiceover_path, display_order)
VALUES
    -- 1: Klimt's Golden Muse (from Dev ID 126)
    (1,
     'Klimt''s Golden Muse',
     'Explore the symbolism and history of Gustav Klimt''s masterpiece and the intellectual rebellion it sparked in Vienna.',
     '## A golden revolution in art

You are looking at one of the most famous images of the early twentieth century. This is Gustav Klimt''s first portrait of Adele Bloch-Bauer. It represents the peak of the Vienna Secession movement. This was a group of artists who wanted to break free from traditional styles. They believed art should be a total experience that merges painting and design. For them, gold was not just a color. It was a tool to transform a human being into a sacred icon of modern life.

## Breaking the rules of the academy

Klimt and his peers rejected the stiff realism taught in old art schools. They felt that traditional styles could no longer express the fast-paced world of 1907. Instead, Klimt looked back to ancient Byzantine mosaics for inspiration. You can see this in how Adele''s body almost disappears into the background. She is wrapped in a shimmering cloak of geometric shapes and gold leaf. By flattening the space, Klimt forces you to focus on the mood rather than a realistic scene.

## Symbols of a modern world

The patterns surrounding Adele are not random. They are a coded language of modern ideas. Notice the repeated eye shapes and triangles on her dress. These symbols reflect the era''s deep interest in psychology and ancient history. Many believe the eyes represent a gaze that looks inward toward the soul. This was a time when Sigmund Freud was exploring the human mind in Vienna. Klimt used these patterns to show that there is always a secret world beneath the surface.

## The woman behind the gold

Adele Bloch-Bauer was much more than just a model. She was a wealthy intellectual and a prominent patron of the arts. Her home was a meeting place for the city''s greatest thinkers and musicians. Klimt took three years to complete this painting because he was fascinated by her presence. The history of the work itself is also a dramatic human saga. It was stolen by the Nazis during the Second World War. Decades later, Adele''s niece fought a famous legal battle to bring the painting back to her family.',
     'samples/1.jpg',
     'samples/1.mp3',
     1),

    -- 2: Venice's Winged Brand (from Prod ID 1565)
    (2,
     'Venice''s Winged Brand',
     'Discover how a winged lion and a Latin greeting became the ultimate symbol of Venetian power.',
     '## The branding of a republic

The winged lion you see is the ultimate logo of the Venetian Republic. Vittore Carpaccio painted this masterpiece in 1516 to project a message of stability and divine favor. For centuries, this creature appeared on flags, coins, and ships across the Mediterranean. It told the world that Venice was protected by Saint Mark himself. By choosing a lion, the city claimed the qualities of majesty, courage, and strength. It was a brilliant piece of political branding that made the state feel ancient and invincible.

## A prophecy in a book

Look closely at the Latin words in the open book. They translate to Peace be with you, Mark, my evangelist. According to local legend, an angel spoke these exact words to the saint in the Venetian lagoon. The angel prophesied that Mark would one day find his final rest here. This story was vital to the Venetian identity. It gave the city a sacred reason to bring the saint''s relics here from Egypt. The open book signifies that the city is at peace. If the lion were shown with a closed book or a sword, it would signal that Venice was at war.

## One foot on land and sea

Notice the unique posture of the lion in this specific painting. His front paws rest firmly on the grassy shore while his hind legs are submerged in the water. This represents the dual nature of the Venetian Empire. It shows their command over the mainland and their dominance over the sea. In the background, you can see the Doge''s Palace exactly as it looked five centuries ago. Carpaccio even painted the intricate red and blue merchant ships docked at the pier. This makes the work a rare snapshot of a vanished era. It captures the moment when Venice was the wealthiest gateway between East and West.',
     'samples/2.jpg',
     'samples/2.mp3',
     2),

    -- 3: A Nation's Golden Anchor (from Prod ID 1570)
    (3,
     'A Nation''s Golden Anchor',
     'Explore the political secrets and personal sacrifices behind Budapest''s most iconic riverfront landmark.',
     '## A stone claim to sovereignty
You are looking at the Hungarian Parliament Building. It is the third largest parliament in the world. This massive structure was built to celebrate Hungary''s 1000th anniversary in 1896. At the time, Hungary was part of the Austro-Hungarian Empire. The leaders in Budapest wanted a building that screamed independence. They wanted to show that their city was a true European capital. The architecture is a bold statement of national pride and political ambition.

## The logic of the chosen style
The architect chose a Neo-Gothic style for the exterior. This was a deliberate choice. It was inspired by the British Houses of Parliament in London. By mimicking London, the designers were aligning Hungary with western democratic traditions. However, the central dome is a Renaissance element. This mix was intended to symbolize two ideas. The spires represent the soaring spirit of the people. The dome represents the unity of the nation''s different regions.

## The secret code of numbers
If you could measure the height of that central dome, you would find it is exactly 96 meters. This number is not an accident. It refers to the year 896 when the first Hungarian tribes arrived in this region. The designers used architecture to bake history into the very dimensions of the city. To ensure this idea stayed dominant, no other building in Budapest was allowed to be taller. It remains a physical cap on the skyline to this day.

## The architect''s final sacrifice
There is a poignant human story behind these grand walls. The lead architect was a man named Imre Steindl. He won the design competition and spent nearly 20 years overseeing the construction. He poured his entire life into this one project. Tragically, Steindl went blind before the building was completed. He died just weeks before the official inauguration in 1902. He never got to see the golden light reflecting off the Danube as you see it now.',
     'samples/3.jpg',
     'samples/3.mp3',
     3),

    -- 4: Feast in the House of Levi (from Prod ID 1618)
    (4,
     'Feast in the House of Levi',
     'A massive 16th-century banquet that was once too scandalous for the Church.',
     '## A banquet for the eyes

You are standing before one of the largest oil paintings in the world. This massive canvas by Paolo Veronese is nearly thirteen meters wide. It was designed to fill an entire wall of a monastery dining room. The three grand arches act like a window. They create an illusion of deep space. Notice how the painted Corinthian columns match the real architecture of a grand Venetian palace. The perspective is so perfect it feels like you could step onto the checkered floor.

## The craft of Venetian luxury

Veronese was a master of material and color. Look closely at the figures dressed in contemporary 16th-century fashion. The man on the far right wears a shimmering striped tunic. You can almost feel the weight of the heavy silk. The deep reds and vibrant blues were created using the most expensive pigments available. Ground-up lapis lazuli gives the sky its intense depth. Even the dog sitting in the foreground has a realistic, wiry coat. These details were meant to celebrate the immense wealth and craft of Venice. Every silver platter and glass carafe catches the light as if it were real.

## A title to save a life

This painting holds a hidden story of survival. It was originally commissioned as a depiction of the Last Supper. However, the Catholic Church was in the middle of a strict religious crackdown. In 1573, the Inquisition summoned Veronese to explain his work. They were furious that he included "buffoons, drunkards, and Germans" in a holy scene. They even hated the dog. To them, these extras were a sign of disrespect.

Veronese faced a dangerous choice. He could repaint the masterpiece or face a heresy trial. Instead, he made a clever move. He simply changed the name of the painting. By calling it the "Feast in the House of Levi," he referenced a different biblical party. This story allowed for a rowdy crowd. The name change satisfied the inquisitors and saved his life. The painting remained exactly as he intended.',
     'samples/4.jpg',
     'samples/4.mp3',
     4),

    -- 5: Venice's Golden Ascent (from Prod ID 1640)
    (5,
     'Venice''s Golden Ascent',
     'Walk the path of Venetian nobles under a ceiling designed to overwhelm and impress.',
     '## The path of the Venetian elite

As you look up, you are seeing the Scala d''Oro, or the Golden Staircase, inside the Doge''s Palace. For centuries, this was the exclusive entrance for the most important people in Venice. Only nobles whose names appeared in the Golden Book could climb these stairs. It was designed to make every visitor feel the immense power of the Republic. Imagine walking here in heavy silk robes and velvet caps. The echo of your boots would announce your arrival to the councils above.

## A stage for high-stakes diplomacy

This staircase served as a high-stakes psychological tool. Ambassadors from foreign empires stood exactly where you are standing now. They looked up at these same figures of Justice and Fortitude. The goal was to remind them that Venice was wealthy and morally superior. If you were a guest, this ceiling was your first lesson in Venetian diplomacy. It told you that the men you were about to meet were untouchable.

## The sculptor who captured movement

The man behind this vision was the sculptor Alessandro Vittoria. In the mid-1500s, he was the rising star of Venetian art. He wanted to create something more dynamic than a flat painted ceiling. Notice how the white figures seem to lean out from the frames. He populated the vault with gods and allegories that appear almost alive. Every figure was a silent witness to the political deals made in the rooms ahead.

## Masterpieces made from marble dust

While it looks like solid carved stone, this ceiling is actually a masterpiece of stucco. Craftsmen mixed marble dust with lime and water to create a soft paste. They had to work incredibly fast before the mixture hardened in the humid lagoon air. Once the shapes were set, they applied thin sheets of 24-karat gold leaf. The gold reflects the light upward to hide any shadows in the corners. It is a fragile shell of dust and light that has survived for five hundred years.',
     'samples/5.jpg',
     'samples/5.mp3',
     5),

    -- 6: The General of Vítkov (from Prod ID 1681)
    (6,
     'The General of Vítkov',
     'Stand before the massive bronze general who defined the spirit of a nation.',
     '## The general who never lost

You are looking at Jan Žižka. He was a 15th-century military genius who famously never lost a single battle. This massive bronze figure sits atop Vítkov Hill in Prague. It is one of the largest equestrian statues in the world. Žižka led a group called the Hussites. These were religious reformers who fought against powerful Catholic crusaders. To many people here, he represents the idea of a small nation standing firm. He is a symbol of grit and tactical brilliance.

## A hill of holy war

This specific spot matters. In July 1420, Žižka and his men defended this ridge against thousands of professional soldiers. The victory here saved Prague. It turned a religious movement into a powerful military force. The memorial building behind the statue was built later to honor Czechoslovak legionaries. These were soldiers who fought for independence during World War One. Linking Žižka to modern soldiers was a deliberate choice. It connected 15th-century heroism to the birth of a modern republic.

## The sculptor''s grand obsession

Sculptor Bohumil Kafka spent years perfecting this work. He did not just want a generic horse and rider. He consulted historians to ensure the armor and weapons were accurate. He even studied anatomy to make the horse appear powerful and alive. Unfortunately, Kafka died just before the statue was finally cast in bronze. It was eventually unveiled in 1950. The relief below the horse shows a lion. It carries a shield representing the union of the Czech and Slovak people.

## Nine tons of bronze muscle

The sheer scale of this object is staggering. The statue stands over nine meters tall. It weighs roughly sixteen and a half tons. Look at the horse''s massive legs and thick neck. Every muscle is tensed as if the animal is about to charge. The figure of Žižka holds a heavy mace. This was his preferred weapon on the battlefield. From this angle, you can see how the bronze has weathered over decades. It stands as a heavy, permanent anchor for the city''s identity.',
     'samples/6.jpg',
     'samples/6.mp3',
     6),

    -- 7: Sobieski at Vienna (from Prod ID 1771)
    (7,
     'Sobieski at Vienna',
     'King Jan III Sobieski leads the legendary 1683 charge that broke the Ottoman siege and saved Vienna.',
     '## A collision of empires

This painting captures the exact moment the map of Europe was rewritten. It depicts the Battle of Vienna in September 1683. At the time, the Ottoman Empire had surrounded the city and brought it to the brink of collapse. This was seen as much more than a local conflict. It was an existential clash of ideas between the East and the West. If Vienna fell, the road into the heart of the Holy Roman Empire would be wide open. This battle represented the idea of the "Bulwark of Christendom." It was a rallying cry that brought together soldiers from across the continent to defend a shared identity.

## The king who answered the call

The man commanding your attention on the white horse is King Jan III Sobieski of Poland. He arrived at the eleventh hour with a massive relief force. Sobieski was a brilliant tactician who understood that the siege could only be broken by a single, overwhelming blow. He led the largest cavalry charge in history to shatter the Ottoman lines. Look at his raised saber and the calm authority in his eyes. To his contemporaries, he was a hero of mythic proportions. After the victory, he sent a letter to the Pope. He wrote, "We came, we saw, and God conquered." This humble message masked his role as the architect of the greatest military triumph of the age.

## Camels and cannons in the dust

Now, look past the central figures toward the edges of the fray. On the right, you can see camels moving through the smoke of the Ottoman camp. These animals carried the massive silk tents and supplies of the Grand Vizier''s army. Their presence creates a striking visual contrast with the armored European horses in the foreground. You can also spot the red flags bearing the white crescent moon of the Ottoman forces. These objects and animals tell a story of a global empire that had marched thousands of miles. The painting uses these details to show how two different worlds literally collided on the hills overlooking the city.',
     'samples/7.jpg',
     'samples/7.mp3',
     7)

ON CONFLICT (id) DO NOTHING;

-- Reset sequence to max id
SELECT setval('sample_discoveries_id_seq', (SELECT COALESCE(MAX(id), 0) FROM sample_discoveries));
