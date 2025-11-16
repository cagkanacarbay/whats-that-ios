import type { PromptConfig } from '../../types.ts';

export const userPromptMetadata: PromptConfig = {
  name: "SINGULAR_USER_PROMPT",
  description: "Context payload for GEPA-optimized discovery generation",
  version: "0.5.1",
  author: "What's That Team",
  variables: [
    "locationContext",
    "recentFullDiscoveries",
    "userDiscoveryContext",
    "customContext"
  ],
  format: {
    markdown: true,
    json: false
  },
  style: {
    tone: "knowledgeable guide, traveler-focused, entertaining",
    length: 'standard',
    focus: ["context integration", "anti-repetition", "clarity"]
  }
};

export const userPromptContent = `Transform a “discovery stimulus” (image, coordinates, and context) into a polished audio guide narrative as described in your system prompt: produce the guided narrative plus strict metadata, following all structure and tone requirements.

# Discovery context

## Location signal
{locationContext}

## Detailed recent discoveries (latest first)
{recentFullDiscoveries}

## Aggregated discovery history
{userDiscoveryContext}

## Custom context from the app team
{customContext}

Task - Apply your overal approach defined in the system prompt to deliver a delightful discovery for the user.
`.trim();
