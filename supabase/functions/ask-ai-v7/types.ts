// Type definitions for the prompt system

export interface PromptConfig {
  name: string;
  description: string;
  version: string;
  author?: string;
  format?: {
    markdown?: boolean;
    json?: boolean;
    jsonSchema?: Record<string, any>;
  };
  style?: {
    tone?: string;
    length?: 'concise' | 'standard' | 'detailed';
    focus?: string[];
  };
  variables?: string[]; // List of variable placeholders this prompt expects
  categories?: string[]; // List of categories to include
  outputSchema?: Record<string, { type: string; desc: string }>;
  responseFormat?: Record<string, string>;
}

export interface AssembledPrompt {
  system: string;
  user: string;
}