import type { Logger } from '../_shared/logger.ts';
import type { PromptConfig, AssembledPrompt } from './types.ts';
import { systemPromptContent } from './prompts/system-prompt.ts';
import { userPromptContent, userPromptMetadata } from './prompts/user-prompt.ts';

/**
 * Replace variables in prompt content
 */
export function replaceVariables(
  content: string,
  variables: Record<string, string>,
  logger?: Logger
): string {
  logger?.debug('Replacing variables in content');
  
  let result = content;
  
  // Replace each variable with its value
  for (const [key, value] of Object.entries(variables)) {
    const placeholder = `{${key}}`;
    // Count occurrences before replacement
    const occurrences = (result.match(new RegExp(placeholder.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&'), 'g')) || []).length;
    
    if (occurrences > 0) {
      logger?.debug('Replacing placeholder', {
        placeholder,
        occurrences,
        valueLength: value?.length ?? 0,
      });
      // Ensure value is a string, handle null/undefined
      result = result.replace(new RegExp(placeholder.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&'), 'g'), String(value ?? ''));
    }
  }
  
  // Look for any remaining unreplaced variables
  const remainingVars = result.match(/\{[a-zA-Z0-9_]+\}/g);
  if (remainingVars) {
    logger?.warn('Unreplaced variables found', { placeholders: remainingVars });
  } else {
    logger?.debug('All expected variable placeholders replaced');
  }
  
  return result;
}

/**
 * Assemble a complete prompt for the AI
 */
export async function assemblePrompt(
  promptType: 'singular',
  variables: Record<string, string> = {},
  logger?: Logger
): Promise<AssembledPrompt> {
  logger?.debug('Assembling prompt', { promptType });
  
  let config: PromptConfig;
  let rawSystemPrompt: string;
  let rawUserPrompt: string;
  
  switch (promptType) {
    case 'singular':
      config = userPromptMetadata;
      rawSystemPrompt = systemPromptContent;
      rawUserPrompt = userPromptContent;
      break;
    default:
      throw new Error(`Unknown prompt type: ${promptType}`);
  }
  
  // Check which variables are expected vs provided
  if (config.variables && Array.isArray(config.variables)) {
    const providedKeys = Object.keys(variables);
    const missingVars = config.variables.filter(expectedVar => 
      !providedKeys.includes(expectedVar)
    );
    
    if (missingVars.length > 0) {
      logger?.warn('Missing expected variables for prompt', { promptType, missingVars });
    }
    
    const extraVars = providedKeys.filter(providedVar => 
      !(config.variables || []).includes(providedVar)
    );
    if (extraVars.length > 0) {
      logger?.debug('Extra variables provided', { promptType, extraVars });
    }
  }
  
  // Replace variables in both prompts
  logger?.debug('Processing system prompt');
  const processedSystemPrompt = replaceVariables(rawSystemPrompt, variables, logger);
  logger?.debug('Processing user prompt');
  const processedUserPrompt = replaceVariables(rawUserPrompt, variables, logger);
  
  logger?.debug('Prompt assembly complete');
  
  return {
    system: processedSystemPrompt,
    user: processedUserPrompt
  };
}
