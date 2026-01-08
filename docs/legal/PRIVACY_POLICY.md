# Privacy Policy — “What’s That?”

Effective date: 8 January 2026
Version: 1.0

This Privacy Policy explains how we collect, use, disclose, and protect information about you when you use the “What’s That?” mobile application and related services (the “Service”).

By using the Service, you acknowledge this Policy. If you do not agree, do not use the Service.

1) Who we are
- Controller: Cha Labs SIA, Eduarda Smiļģa iela 32 – 19, Rīga, LV-1002

2) What we collect
We collect the types of data described below. Exact fields depend on how you use the Service and OS permissions you grant.

- Account data: email address; authentication state (via Supabase). If you use Google Sign‑In, we receive an ID token that Supabase exchanges for a session; we do not receive your Google password.
- Content you submit: photos you take or upload; text or other inputs. Photos may contain EXIF metadata (e.g., timestamp, GPS) if present. We may perform OCR/transcription and translation on text found in images to support analysis.
- Location data (optional): precise or approximate location when you grant OS permission. We may also fetch nearby points of interest using your coordinates to improve context.
- Push notifications: APNs device token (iOS); device name and platform to route notifications.
- Discovery history: a record of your prior "discoveries," including their titles, descriptions, and timestamps. We use this history to personalize future analysis prompts.
- Device permissions: We request OS permissions for specific features (for example, camera/photos for capture/upload; save to photo library for photos taken while in app; location for context; notifications for status updates). You can revoke these permissions at any time in OS settings.
- AI outputs: titles, descriptions, and analysis generated for your images; Audio Guide narrations generated for your discoveries.
- Audio Guides: If you generate Audio Guides, we store the AI‑generated audio files in our systems. Audio files are also cached locally on your device (automatically managed) for offline playback. We store your voice preference selection and playback speed settings.
- In‑app purchases: productId, transaction identifiers (e.g., original transaction id), and platform. We do not store raw receipt data or your full payment card details.
- Technical data: device/OS version, app version, IP address, and similar diagnostic information. We do not embed third‑party analytics/crash SDKs at this time.
- Identities for anti-fraud: We process identifiers (such as device IDs and hashed email addresses) to prevent abuse of the Service. This collection is mandatory to ensure fair usage of free tiers/credits.
Avoid sensitive data: Please avoid uploading images or text that reveal highly sensitive personal information (e.g., medical, financial, government IDs). While our app is designed for places/objects, images may inadvertently capture people or personal data.

3) Sources
- You: when you register, take/upload a photo, or otherwise interact.
- Device sensors: camera, photos library, and location (with permission).
- Service providers: AI provider(s) process your photo and context to generate outputs; mapping provider(s) return nearby places data; app stores return transaction confirmations.

4) How we use data and legal bases (GDPR)
- Provide and operate the Service (create accounts, process images, return AI outputs, maintain your discoveries, verify in‑app purchases): contract (Art. 6(1)(b)).
- Use discovery history in prompts (to provide relevant context and improve results): contract (Art. 6(1)(b)). This is an integral part of how the Service functions.
- Location and nearby places (to enrich context): consent via OS permissions (Art. 6(1)(a)).
- Push notifications (e.g., when analysis completes): consent via OS (Art. 6(1)(a)).
- Marketing and publicity (use of discoveries): as permitted under the license you grant in our Terms of Service. See Section 3 of the Terms of Service for details.
- Security, fraud prevention, abuse detection, debugging: legitimate interests (Art. 6(1)(f)).
- Legal compliance and recordkeeping (e.g., tax/transaction records): legal obligation (Art. 6(1)(c)).

We do not use your personal information for third‑party advertising. We do not sell or “share” (as defined by CPRA) your personal information.

5) AI providers and model training posture
- We send user images and context (including location or nearby places where provided) to AI provider(s) solely to generate outputs. Examples include Anthropic Claude, Google Gemini, and OpenAI for image analysis, and Fish Audio for Audio Guide narrations. We may add or change providers.
- For Audio Guides, we send your discovery's text description to Fish Audio to generate audio narrations. The provider processes this text solely to produce the audio file, which is then stored in our systems and cached on your device for playback.
- Our primary AI providers (Anthropic Claude, Google Gemini via paid API, and OpenAI) have confirmed that API data is not used to train their foundation models by default. For Fish Audio and any other providers, we rely on their stated policies, which may vary; we configure integrations to minimize data retention where options are available. Providers may retain limited data transiently for abuse prevention and troubleshooting per their policies.

6) Sharing and recipients
We share data with service providers who act on our behalf to provide the Service:
- Supabase (auth, database, storage, serverless) — stores account data, discoveries, images (storage), audio files, and push tokens.
- AI provider(s) (e.g., Anthropic Claude, Google Gemini, OpenAI) — process your inputs to produce outputs.
- Fish Audio (text‑to‑speech) — receives discovery text descriptions to generate Audio Guide audio files.
- Mapping provider(s) (e.g., Google Places API) — receive your coordinates to return nearby places.
- Apple (push service via APNs) — receives your device token and notification payloads.
- Apple (in‑app purchases) — processes payments and validates receipts.

We may also disclose information if required by law or to protect our rights, users, or the Service, and in connection with corporate transactions.

7) Share links (user‑initiated)
If you create a share link for a discovery, the link uses a non‑guessable identifier (e.g., UUID). Anyone who has the link can view the shared page and may re‑share it. We do not list or index share links in our app, and we set pages to discourage search indexing where supported, but we cannot control third‑party indexing or resharing. We do not include precise GPS coordinates or EXIF location data on shared pages; however, the image itself may imply a general location (e.g., recognizable landmarks). You can stop future access by deleting the discovery or disabling the share link (where available); previously shared copies or reposts may persist.

8) International transfers
Our primary infrastructure (Supabase) is hosted in the European Union (Germany, Frankfurt region). AI service providers (Anthropic Claude, Google Gemini, OpenAI, Fish Audio) and mapping providers (Google Places) may process data in the United States and other countries. Apple processes push notifications globally. Where data is transferred outside the EEA/UK, we rely on safeguards such as Standard Contractual Clauses (SCCs) and provider Data Processing Agreements (DPAs). Contact us at privacy@chalabs.xyz for copies of relevant transfer mechanisms where legally permissible.

9) Retention
- Account data: while your account is active. If you request deletion, we will delete or anonymize within a reasonable period, subject to legal retention obligations.

To prevent abuse of initial free credit offers, we retain non-reversible SHA-256 hashes of account identifiers (such as email and device IDs) even after account deletion. These hashes do not allow us to reconstruct your original personal information.
- Photos and AI outputs: retained until you delete the associated discovery or delete your account.
- Audio Guides: retained until you delete the associated discovery or delete your account. Local device cache is automatically managed and cleared when you sign out or delete the app.
- Push tokens: invalidated or deleted when you log out, uninstall, or after 12 months of inactivity.
- Receipts/transactions: retained for the period required by tax/financial laws; raw receipt payloads are minimized or not stored beyond validation.
- Logs/diagnostics: typically retained ≤ 90 days in production; debug logs are minimized and redacted.
- Caches/backups: temporary processing caches are short‑lived; backups expire on a scheduled rotation.

10) Security
We use technical and organizational measures designed to protect personal information (e.g., TLS in transit, encryption at rest, role‑based access controls including database row‑level security, private storage buckets with signed URLs, least‑privilege access, and audit logging). No system is perfectly secure; we cannot guarantee absolute security. You should keep your device and account credentials secure.

11) Your rights (GDPR/UK GDPR)
Subject to exceptions, you can request: access, rectification, deletion, restriction, objection to processing, and portability. Where processing is based on consent (e.g., location, notifications), you can withdraw consent at any time in OS settings or in‑app.

To exercise your rights, email privacy@chalabs.xyz with your request. We will respond within 30 days. We may need to verify your identity before processing your request. You may lodge a complaint with your supervisory authority.

12) California privacy (CCPA/CPRA)
We do not sell or share your personal information. You have rights to know, access, delete, and correct certain information. You can designate an authorized agent. Sensitive information (precise location) is used only to provide the Service you request and is not used for inferring characteristics.

13) Children
The Service is not directed to children under 13 (or under 16 in the EEA). We do not knowingly collect personal information from children. If you believe a child provided personal information, contact us and we will take appropriate steps.

14) Cookies/SDKs/Tracking
We do not embed third‑party analytics or advertising SDKs at this time. If we add analytics or crash reporting in the future, we will update this Policy and, where required, provide controls or obtain consent. Browsers’ “Do Not Track” signals are not consistently honored by mobile apps; we currently do not respond to DNT.

15) Automated decision‑making
The Service uses AI to generate descriptive content for images, but we do not make automated decisions that produce legal or similarly significant effects about you.

16) Changes to this Policy
We may update this Policy from time to time. If we make material changes, we will notify you (e.g., in‑app or by email). Continued use of the Service after changes take effect means you accept the updated Policy.

17) Contact
Questions or requests: privacy@chalabs.xyz
Postal mail: Eduarda Smiļģa iela 32 – 19, Rīga, LV-1002


