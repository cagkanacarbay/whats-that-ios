INSERT INTO public.voice_inventory (provider, tts_model, voice_model_id, display_name) VALUES
  ('fish','s1','bf322df2096a46f18c579d0baa36f41d','Adrian'),
  ('fish','s1','933563129e564b19a115bedd57b7406a','Sarah'),
  ('fish','s1','536d3a5e000945adb7038665781a4aca','Ethan'),
  ('fish','s1','e3cd384158934cc9a01029cd7d278634','Laura')
ON CONFLICT DO NOTHING;
