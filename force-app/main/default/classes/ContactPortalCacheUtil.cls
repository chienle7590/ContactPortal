/**
 * Utility class for cache operations in the Contact Portal
 */
public with sharing class ContactPortalCacheUtil {
    
    private static final String EMAIL_CHANGE_CACHE_PREFIX = 'EmailChange_';
    
    /**
     * Generates a cache key for access control
     * 
     * @param contactId The contact ID
     * @param userId The user ID
     * @return String The cache key
     */
    public static String generateAccessCacheKey(Id contactId, Id userId) {
        // Remove all non-alphanumeric characters to create valid cache key
        String cleanContactId = String.valueOf(contactId).replaceAll('[^a-zA-Z0-9]', '');
        String cleanUserId = String.valueOf(userId).replaceAll('[^a-zA-Z0-9]', '');
        
        // Create alphanumeric-only cache key
        String cacheKey = 'contactaccess' + cleanContactId + cleanUserId;
        
        System.debug('Generated access cache key: ' + cacheKey);
        return cacheKey;
    }
    
    /**
     * Generates a cache key for login verification codes
     * 
     * @param email The email address
     * @return String The cache key
     */
    public static String loginCodeCacheKey(String email) {
        return 'VerifyCode' + email.replaceAll('[^a-zA-Z0-9]', '');
    }
    
    /**
     * Generates a cache key for email change verification
     * 
     * @param contactId The contact ID
     * @return String The cache key
     */
    public static String emailChangeCacheKey(Id contactId) {
        return EMAIL_CHANGE_CACHE_PREFIX + String.valueOf(contactId).replaceAll('[^a-zA-Z0-9]', '');
    }
    
    /**
     * Generates a random 6-digit code
     * 
     * @return String The random code
     */
    public static String random6Digits() {
        Integer n = (Integer)(Math.floor(Math.random() * 900000) + 100000);
        if (n > 999999) {
            n = 999999;
        }
        return String.valueOf(n);
    }
}