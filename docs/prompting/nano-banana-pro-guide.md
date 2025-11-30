# The Complete Guide to Nano-Banana Pro: 10 Tips for Professional Asset Production

Nano-Banana Pro moves from playful image generation to production-grade assets with strengths in text rendering, character consistency, visual synthesis, real-world grounding (Search), and high-resolution (up to 4K) output. Use this guide as a reference for prompting patterns and capabilities.

Source: Guillaume Vernade, Gemini Developer Advocate, Google DeepMind.

## 0. The Golden Rules of Prompting

- Nano-Banana Pro is a thinking model—brief it like a creative partner instead of listing tags.
- Edit, don’t re-roll: ask for specific fixes when you’re close.  
  Example: “That’s great, but change the lighting to sunset and make the text neon blue.”
- Use natural language and full sentences.  
  Bad: “Cool car, neon, city, night, 8k.”  
  Good: “A cinematic wide shot of a futuristic sports car speeding through a rainy Tokyo street at night. The neon signs reflect off the wet pavement and the car’s metallic chassis.”
- Be specific and descriptive about subject, setting, lighting, mood, and materiality (e.g., “matte finish,” “brushed steel,” “soft velvet,” “crumpled paper”).
- Provide context (the “why” or “for whom”) so the model makes logical artistic decisions.  
  Example: “Create an image of a sandwich for a Brazilian high-end gourmet cookbook.”

## 1. Text Rendering, Infographics, and Visual Synthesis

- Excels at legible, stylized text and compressing dense information into visuals.
- State the style (polished editorial, technical diagram, hand-drawn whiteboard) and quote any text you need rendered.
- Example prompts:  
  - “Generate a clean, modern infographic summarizing the key financial highlights from this earnings report. Include charts for ‘Revenue Growth’ and ‘Net Income’, and highlight the CEO’s key quote in a stylized pull-quote box.”  
  - “Make a retro, 1950s-style infographic about the history of the American diner. Include distinct sections for ‘The Food,’ ‘The Jukebox,’ and ‘The Decor.’ Ensure all text is legible and stylized to match the period.”  
  - “Create an orthographic blueprint that describes this building in plan, elevation, and section. Label the ‘North Elevation’ and ‘Main Entrance’ clearly in technical architectural font. Format 16:9.”  
  - “Summarize the concept of ‘Transformer Neural Network Architecture’ as a hand-drawn whiteboard diagram suitable for a university lecture. Use different colored markers for the Encoder and Decoder blocks, and include legible labels for ‘Self-Attention’ and ‘Feed Forward’.”

## 2. Character Consistency and Viral Thumbnails

- Supports up to 14 reference images (6 high fidelity) for identity locking.
- Specify: “Keep the person’s facial features exactly the same as Image 1,” then direct expressions or poses.
- Combine subjects, graphics, and text for thumbnails in one pass.
- Example prompts:  
  - “Design a viral video thumbnail using the person from Image 1. Face Consistency: Keep the person’s facial features exactly the same as Image 1, but change their expression to look excited and surprised. Action: Pose the person on the left side, pointing their finger towards the right side of the frame. Subject: On the right side, place a high-quality image of a delicious avocado toast. Graphics: Add a bold yellow arrow connecting the person’s finger to the toast. Text: Overlay massive, pop-style text in the middle: ‘3分钟搞定!’ (Done in 3 mins!). Use a thick white outline and drop shadow. Background: A blurred, bright kitchen background. High saturation and contrast.”  
  - “Create a funny 10-part story with these 3 fluffy friends going on a tropical vacation. The story is thrilling throughout with emotional highs and lows and ends in a happy moment. Keep the attire and identity consistent for all 3 characters, but their expressions and angles should vary throughout all 10 images. Make sure to only have one of each character in each image.”  
  - “Create 9 stunning fashion shots as if they’re from an award-winning fashion editorial. Use this reference as the brand style but add nuance and variety to the range so they convey a professional design touch. Please generate nine images, one at a time.”

## 3. Grounding with Google Search

- Uses Google Search for real-time data and factual grounding to reduce hallucinations.
- Ask for visualizations of dynamic data (weather, stocks, news, current events).
- Example prompt: “Generate an infographic of the best times to visit the U.S. National Parks in 2025 based on current travel trends.”

## 4. Advanced Editing, Restoration, and Colorization

- Handles in-painting, restoration, colorization, localization, and physics-aware edits via natural language.
- No need to mask manually—describe the desired change.
- Example prompts:  
  - “Remove the tourists from the background of this photo and fill the space with logical textures (cobblestones and storefronts) that match the surrounding environment.”  
  - “Colorize this manga panel. Use a vibrant anime style palette. Ensure the lighting effects on the energy beams are glowing neon blue and the character’s outfit is consistent with their official colors.”  
  - “Take this concept and localize it to a Tokyo setting, including translating the tagline into Japanese. Change the background to a bustling Shibuya street at night.”  
  - “Turn this scene into winter time. Keep the house architecture exactly the same, but add snow to the roof and yard, and change the lighting to a cold, overcast afternoon.”

## 5. Dimensional Translation (2D ↔ 3D)

- Translate 2D schematics into 3D visuals or 3D scenes into 2D plans.
- Example prompts:  
  - “Based on the uploaded 2D floor plan, generate a professional interior design presentation board in a single image. Layout: A collage with one large main image at the top (wide-angle perspective of the living area), and three smaller images below (Master Bedroom, Home Office, and a 3D top-down floor plan). Style: Apply a Modern Minimalist style with warm oak wood flooring and off-white walls across ALL images. Quality: Photorealistic rendering, soft natural lighting.”  
  - “Turn the ‘This is Fine’ dog meme into a photorealistic 3D render. Keep the composition identical but make the dog look like a plush toy and the fire look like realistic flames.”

## 6. High-Resolution and Textures

- Supports native 1K–4K generation; ask explicitly for resolution and specify surface details.
- Example prompts:  
  - “Harness native high-fidelity output to craft a breathtaking, atmospheric environment of a mossy forest floor. Command complex lighting effects and delicate textures, ensuring every strand of moss and beam of light is rendered in pixel-perfect resolution suitable for a 4K wallpaper.”  
  - “Create a hyper-realistic infographic of a gourmet cheeseburger, deconstructed to show the texture of the toasted brioche bun, the seared crust of the patty, and the glistening melt of the cheese. Label each layer with its flavor profile.”

## 7. Thinking and Reasoning

- Generates interim thought images (not charged) to refine composition and solve visual problems.
- Useful for analytical or stepwise visuals.  
  Example: “Solve log_{x^2+1}(x^4-1)=2 in C on a white board. Show the steps clearly.”

## 8. One-Shot Storyboarding and Concept Art

- Produces storyboards or concept art in a single pass; maintain style and composition consistency.
- Example prompt: “Create a one-shot storyboard that visualizes a short sci-fi chase sequence through neon-lit alleys, keeping character silhouettes and vehicle designs consistent across panels.”

## 9. Structural Control and Layout Guidance

- Can obey layout guidance, labels, and structural constraints (e.g., blueprint callouts, labeled diagrams).
- Example prompt: “Design a tri-fold brochure layout with clearly labeled panels for ‘Overview,’ ‘Features,’ and ‘Pricing.’ Include placeholder text boxes and a hero image area, using a clean tech aesthetic.”

## 10. What’s Next?

- Use the model conversationally to iterate—ask for specific deltas instead of starting over.
- Combine reference images, text directives, and layout guidance to reach production-ready assets faster.
