/**
 * Utility class for validating and sanitizing input in the Contact Portal
 */
public with sharing class ContactPortalInputValidator {
    
    /**
     * Validates an email address
     * 
     * @param email The email address to validate
     * @return Boolean True if the email is valid
     */
    public static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        if (email.length() > 100) {
            return false;
        }
        email = email.toLowerCase().trim();
        
        // Enhanced email validation
        if (!Pattern.matches('^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$', email)) {
            return false;
        }
        
        // Block suspicious patterns
        if (email.contains('..') || email.startsWith('.') || email.endsWith('.')) {
            return false;
        }
        
        return true;
    }
    
    /**
     * Sanitizes a name value
     * 
     * @param value The name to sanitize
     * @return String The sanitized name
     */
    public static String sanitizeName(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        
        value = value.trim();
        if (value.length() > 80) {
            value = value.substring(0, 80);
        }
        
        // Remove potentially dangerous characters
        value = value.replaceAll('[<>"\']', '');
        value = value.replaceAll('\\p{Cntrl}', ''); // Remove control characters
        
        return String.isBlank(value) ? null : value;
    }
    
    /**
     * Sanitizes a phone number
     * 
     * @param phone The phone number to sanitize
     * @return String The sanitized phone number
     */
    public static String sanitizePhone(String phone) {
        if (phone == null) {
            return null;
        }
        
        phone = phone.replaceAll('[^0-9+\\-\\s\\(\\)]', '').trim();
        if (phone.length() > 40) {
            phone = phone.substring(0, 40);
        }
        
        return String.isBlank(phone) ? null : phone;
    }
}