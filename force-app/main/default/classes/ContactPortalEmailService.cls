/**
 * Service class for handling email-related operations in the Contact Portal
 */
public with sharing class ContactPortalEmailService {
    
    private static final Integer EMAIL_CHANGE_TTL_MINUTES = 30;
    
    /**
     * Custom exception class for email operations
     */
    public class EmailServiceException extends Exception {}
    
    /**
     * Processes field updates for a contact
     * 
     * @param contact The contact to update
     * @param updates The field updates
     * @param emailChanged Output parameter indicating if email changed
     * @param newEmail Output parameter containing the new email
     */
    public static void processContactFieldUpdates(Contact contact, Map<String,Object> updates, Boolean emailChanged, String newEmail) {
        processNameUpdates(contact, updates);
        processPhoneUpdates(contact, updates);
        processEmailUpdate(contact, updates, emailChanged, newEmail);
    }
    
    /**
     * Processes name field updates
     * 
     * @param contact The contact to update
     * @param updates The field updates
     */
    private static void processNameUpdates(Contact contact, Map<String,Object> updates) {
        if (updates.containsKey('FirstName')) {
            String fn = ContactPortalInputValidator.sanitizeName((String) updates.get('FirstName'));
            if (fn != null) {
                contact.FirstName = fn;
            }
        }
        
        if (updates.containsKey('LastName')) {
            String ln = ContactPortalInputValidator.sanitizeName((String) updates.get('LastName'));
            if (ln != null) {
                contact.LastName = ln;
            }
        }
    }
    
    /**
     * Processes phone field updates
     * 
     * @param contact The contact to update
     * @param updates The field updates
     */
    private static void processPhoneUpdates(Contact contact, Map<String,Object> updates) {
        if (updates.containsKey('Phone')) {
            contact.Phone = ContactPortalInputValidator.sanitizePhone((String) updates.get('Phone'));
        }
        
        if (updates.containsKey('MobilePhone')) {
            contact.MobilePhone = ContactPortalInputValidator.sanitizePhone((String) updates.get('MobilePhone'));
        }
    }
    
    /**
     * Processes email field update
     * 
     * @param contact The contact to update
     * @param updates The field updates
     * @param emailChanged Output parameter indicating if email changed
     * @param newEmail Output parameter containing the new email
     */
    private static void processEmailUpdate(Contact contact, Map<String,Object> updates, Boolean emailChanged, String newEmail) {
        if (updates.containsKey('Email')) {
            String em = (String) updates.get('Email');
            if (em != null) {
                em = em.trim().toLowerCase();
                if (em != contact.Email) {
                    validateNewEmail(em, contact.Id);
                    
                    emailChanged = true;
                    newEmail = em;
                }
            }
        }
    }
    
    /**
     * Validates a new email address
     * 
     * @param email The email to validate
     * @param contactId The contact ID
     */
    private static void validateNewEmail(String email, Id contactId) {
        if (!ContactPortalInputValidator.isValidEmail(email)) {
            throw new EmailServiceException('Invalid email format.');
        }
        
        // CRUD permission check
        if (!Schema.SObjectType.Contact.isAccessible()) {
            throw new EmailServiceException('Insufficient permissions to access contact data.');
        }
        
        // Check if email is already used by another contact
        List<Contact> existingContacts = [
            SELECT Id FROM Contact 
            WHERE Email = :email AND Id != :contactId 
            LIMIT 1
        ];
        
        if (!existingContacts.isEmpty()) {
            throw new EmailServiceException('Email address is already in use.');
        }
    }
    
    /**
     * Handles an email change
     * 
     * @param contactId The contact ID
     * @param newEmail The new email address
     * @param oldEmail The old email address
     * @param responseData The response data to update
     * @return Map<String,Object> The updated response
     */
    public static Map<String,Object> handleEmailChange(Id contactId, String newEmail, String oldEmail, Map<String,Object> responseData) {
        String emailCode = ContactPortalCacheUtil.random6Digits();
        String cacheKey = ContactPortalCacheUtil.emailChangeCacheKey(contactId);
        Map<String,Object> pending = new Map<String,Object>{
            'newEmail' => newEmail,
            'oldEmail' => oldEmail,
            'code' => emailCode,
            'expiry' => System.now().addMinutes(EMAIL_CHANGE_TTL_MINUTES).getTime(),
            'attempts' => 0
        };
        
        Cache.Org.put(cacheKey, JSON.serialize(pending), EMAIL_CHANGE_TTL_MINUTES * 60);
        
        responseData.put('pendingEmail', newEmail);
        responseData.put('emailChangePending', true);
        responseData.put('emailVerificationCode_TEST', emailCode); // REMOVE in production
        
        ContactPortalLogger.logSecurityEvent('EMAIL_CHANGE_INITIATED', oldEmail, 
            'Email change from ' + oldEmail + ' to ' + newEmail);
        
        return ContactPortalController.ok(new Map<String,Object>{
            'message' => 'Contact updated. Email change pending verification.',
            'contact' => responseData
        });
    }
}