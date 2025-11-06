import type { Logger } from '../_shared/logger.ts';

// Field mask for the Places API response
export const googleFieldMask: string[] = [
  'places.formattedAddress',
  'places.adrFormatAddress',
  'places.displayName',
  'places.googleMapsUri',
  'places.id',
  'places.location',
  'places.name',
  'places.primaryType',
  'places.primaryTypeDisplayName',
  'places.subDestinations',
  'places.types'
];

// Define types for coordinates and places data for better type safety
export interface Coordinates {
  latitude: number;
  longitude: number;
}

export interface Place {
  formattedAddress?: string;
  adrFormatAddress?: string;
  displayName?: { text: string };
  googleMapsUri?: string;
  id?: string;
  location: Coordinates;
  name?: string;
  primaryType?: string;
  primaryTypeDisplayName?: { text: string };
  subDestinations?: any[];
  types?: string[];
}

export interface LocationInfo {
  city: string;
  district: string;
  country: string;
  streetName: string;
  postalCode: string;
}

// Add types to function parameters
export const createRequestBody = (latitude: number, longitude: number) => {
  return {
    // https://developers.google.com/maps/documentation/places/web-service/nearby-search#includedtypesexcludedtypes,-includedprimarytypesexcludedprimarytypes
    includedPrimaryTypes: [
      "art_gallery",
      "museum",
      "performing_arts_theater",
      "library",
      "university",
      "amusement_center",
      "amusement_park",
      "aquarium",
      "community_center",
      "convention_center",
      "cultural_center",
      "dog_park",
      "event_venue",
      "hiking_area",
      "historical_landmark",
      "marina",
      "movie_theater",
      "national_park",
      "night_club",
      "park",
      "tourist_attraction",
      "zoo",
      "city_hall",
      "courthouse",
      "embassy",
      "local_government_office",
      "campground",
      "church",
      "hindu_temple",
      "mosque",
      "synagogue",
      "market",
      "athletic_field",
      "golf_course",
      "ski_resort",
      "sports_club",
      "sports_complex",
      "stadium",
      "airport",
      "ferry_terminal"
    ],
    maxResultCount: 10,
    locationRestriction: {
      circle: {
        center: {
          latitude,
          longitude
        },
        radius: 250.0
      }
    }
  };
};

// Add types to function parameters
export const fetchNearbyPlaces = async (
  latitude: number,
  longitude: number,
  logger?: Logger
): Promise<Place[] | null> => {
  try {
    const requestBody = createRequestBody(latitude, longitude);
    const apiKey = Deno.env.get('GOOGLE_MAPS_API_KEY');
    logger?.debug('Preparing Google Places request', {
      hasApiKey: Boolean(apiKey),
      latitude,
      longitude,
    });
    const response = await fetch('https://places.googleapis.com/v1/places:searchNearby', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey ?? '',
        'X-Goog-FieldMask': googleFieldMask.join(',')
      },
      body: JSON.stringify(requestBody)
    });
    if (!response.ok) {
      const errorText = await response.text();
      logger?.error('Google Places API error', {
        status: response.status,
        statusText: response.statusText,
        responseBodyLength: errorText.length,
      });
      return null;
    }
    const data = await response.json();
    logger?.debug('Google Places response received', {
      placeCount: Array.isArray(data?.places) ? data.places.length : 0,
    });
    return data.places as Place[]; // Cast to Place[]
  } catch (error: any) {
    logger?.error('Error calling Google Places API', { errorMessage: error?.message ?? String(error) });
    return null;
  }
};


// Add types to parameters
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3; // Earth's radius in meters
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in meters
}

// Add type for location parameter
export interface NearbyPlacesContextPayload {
  summary?: string;
  distanceMeters?: number;
  horizontalAccuracyMeters?: number;
  distanceUncertaintyMeters?: number;
}

export interface HandleNearbyPlacesLocation {
  coords: Coordinates;
  nearbyPlaces?: Place[];
  nearbyPlacesContext?: NearbyPlacesContextPayload;
}

// Add type for return value
export interface HandleNearbyPlacesResult {
  nearbyPlacesInfo: string; // This is now less relevant
  placesData: Place[] | null;
}

// This function is still used by index.ts to fetch data if needed
export async function handleNearbyPlaces(
  location: HandleNearbyPlacesLocation | null,
  logger?: Logger
): Promise<HandleNearbyPlacesResult> {
  let placesData: Place[] | null = null;
  if (location) {
    if (location.nearbyPlaces) {
      logger?.debug('Using cached nearby places', {
        cachedCount: location.nearbyPlaces.length,
      });
      placesData = location.nearbyPlaces;
    } else {
      logger?.debug('Fetching nearby places for coordinates', {
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
      });
      placesData = await fetchNearbyPlaces(
        location.coords.latitude,
        location.coords.longitude,
        logger
      );
    }
  }
  return {
    nearbyPlacesInfo: '', // Kept for compatibility
    placesData
  };
}

// Add types to parameters and return value
export function extractLocationInfo(places: Place[]): LocationInfo {
  if (!places || places.length === 0) return {
    city: '', district: '', country: '', streetName: '', postalCode: ''
  };
  
  let city = '', district = '', country = '', streetName = '', postalCode = '';
  
  for (const place of places) {
    if (place.adrFormatAddress) {
      // Extract each component using regex on the HTML structure
      const localityMatch = place.adrFormatAddress.match(/<span class="locality">([^<]+)<\/span>/);
      const countryMatch = place.adrFormatAddress.match(/<span class="country-name">([^<]+)<\/span>/);
      const regionMatch = place.adrFormatAddress.match(/<span class="region">([^<]+)<\/span>/);
      const streetMatch = place.adrFormatAddress.match(/<span class="street-address">([^<]+)<\/span>/);
      const postalMatch = place.adrFormatAddress.match(/<span class="postal-code">([^<]+)<\/span>/);
      
      if (localityMatch && localityMatch[1]) city = localityMatch[1];
      if (countryMatch && countryMatch[1]) country = countryMatch[1];
      if (regionMatch && regionMatch[1]) district = regionMatch[1];
      if (streetMatch && streetMatch[1]) streetName = streetMatch[1];
      if (postalMatch && postalMatch[1]) postalCode = postalMatch[1];
      
      // If we found all the key information, break the loop
      if (city && country) break;
    }
  }
  
  if (!city || !country) {
    for (const place of places) {
      if (place.formattedAddress) {
        const addressParts = place.formattedAddress.split(',').map((part: string) => part.trim());
        
        if (addressParts.length >= 2) {
          // Last part is typically the country
          if (!country) country = addressParts[addressParts.length - 1];
          
          // Check if we have a postal code in the second-to-last part
          const postalCodeMatch = addressParts[addressParts.length - 2].match(/([A-Z]{2}-\d+)/);
          if (postalCodeMatch) {
            if (!postalCode) postalCode = postalCodeMatch[1];
            
            // If there's a postal code, look for the city in other parts
            if (!city && addressParts.length >= 3) {
              for (let i = 0; i < addressParts.length - 2; i++) {
                // Skip parts that look like postal codes or are too short
                if (!addressParts[i].match(/([A-Z]{2}-\d+)/) && addressParts[i].length > 2) {
                  city = addressParts[i];
                  break;
                }
              }
            }
          } else if (!city) {
            // If no postal code, assume second-to-last part is the city
            city = addressParts[addressParts.length - 2];
          }
        }
        
        // If we found both city and country, break the loop
        if (city && country) break;
      }
    }
  }
  
  return { city, district, country, streetName, postalCode };
} 
import type { Logger } from '../_shared/logger.ts';
