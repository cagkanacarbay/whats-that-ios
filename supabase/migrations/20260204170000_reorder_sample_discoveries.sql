-- Migration: Reorder sample discoveries for better visual flow
-- New order:
-- 1. Klimt's Golden Muse
-- 2. Venice's Golden Ascent
-- 3. Sobieski at Vienna
-- 4. A Nation's Golden Anchor
-- 5. Feast in the House of Levi
-- 6. The General of Vítkov
-- 7. Venice's Winged Brand

UPDATE sample_discoveries SET display_order = CASE id
    WHEN 1 THEN 1  -- Klimt's Golden Muse (keep at 1)
    WHEN 5 THEN 2  -- Venice's Golden Ascent (move to 2)
    WHEN 7 THEN 3  -- Sobieski at Vienna (move to 3)
    WHEN 3 THEN 4  -- A Nation's Golden Anchor (move to 4)
    WHEN 4 THEN 5  -- Feast in the House of Levi (move to 5)
    WHEN 6 THEN 6  -- The General of Vítkov (keep at 6)
    WHEN 2 THEN 7  -- Venice's Winged Brand (move to 7)
END
WHERE id IN (1, 2, 3, 4, 5, 6, 7);
