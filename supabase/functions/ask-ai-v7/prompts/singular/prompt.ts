import type { PromptConfig } from '../../types.ts';
import { systemPromptContent, systemPromptMetadata } from './system-prompt.ts';
import { userPromptContent, userPromptMetadata } from './user-prompt.ts';

// Export system prompt components
export const singularSystemPrompt = systemPromptContent;
export const singularSystemPromptConfig = systemPromptMetadata;

// Export user prompt components  
export const singularPromptContent = userPromptContent;
export const singularUserPromptConfig = userPromptMetadata;

// Combined config for backward compatibility
export const singularPromptConfig: PromptConfig = {
  name: "SINGULAR_PROMPT_COMBINED",
  description: "Combined singular prompt configuration",
  version: "0.4.2",
  variables: singularUserPromptConfig.variables,
  format: {
    json: false // Mixed format with narrative and JSON
  }
};
