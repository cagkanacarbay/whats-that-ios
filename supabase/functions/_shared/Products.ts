// import { Platform } from 'react-native';

// TODO: Replace with actual Product IDs from App Store Connect
export const ProductIDs = {
  // iOS Product IDs
  ios: {
    CREDITS_PACK_100: '100credits',
    CREDITS_PACK_1000: '1000credits',
  },
  // Android Product IDs
  // android: {
  //   CREDITS_PACK_10: 'whatsthat_credits_10', // Example format
  //   CREDITS_PACK_50: 'whatsthat_credits_50',
  //   CREDITS_PACK_100: 'whatsthat_credits_100',
  // },
};

// Helper function to get platform-specific IDs
export const getPlatformProductIds = (): string[] => {
  // Only return iOS IDs since Android is not currently supported
  return Object.values(ProductIDs.ios);
};

// Helper function to map platform product ID to credit amount (adjust as needed)
export const getCreditsForProductId = (productId: string): number => {
    switch (productId) {
        case ProductIDs.ios.CREDITS_PACK_100:
            return 100;
        case ProductIDs.ios.CREDITS_PACK_1000:
            // Assuming the 1000 pack ID maps to 1000 credits
            return 1000;
        default:
            console.warn(`Unknown product ID: ${productId}`);
            return 0;
    }
} 