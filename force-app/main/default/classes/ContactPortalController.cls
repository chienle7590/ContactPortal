/**
 * Controller for the Contact Portal
 * Provides functionality for contact authentication and management
 */
public with sharing class ContactPortalController {
    
    /**
     * Provides debugging information about the current token state
     * This method is for development/troubleshooting only and should be disabled in production
     * 
     * @param signedToken The token to inspect
     * @return Map<String, Object> Debug information about the token
     */
    @RemoteAction
    public static Map<String, Object> debugTokenState(String signedToken) {
        Map<String, Object> debugInfo = new Map<String, Object>();
        try {
            ContactPortalSecurityService.TokenResult tr = ContactPortalSecurityService.validateSecureToken(signedToken);
            debugInfo.put('tokenValid', tr.valid);
            debugInfo.put('tokenMessage', tr.message);

            if (tr.valid) {
                debugInfo.put('contactId', tr.contactId);
                debugInfo.put('email', tr.verifiedEmail);
                debugInfo.put('issuedAt', tr.issuedAt);
                // Check security context in cache
                String securityKey = ContactPortalSecurityService.getSecurityCacheKey(tr.verifiedEmail, tr.contactId);
                String cachedContext = (String) Cache.Org.get(securityKey);
                debugInfo.put('securityContextExists', !String.isBlank(cachedContext));
                // Check access permissions
                String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(tr.contactId, UserInfo.getUserId());
                String cachedAccess = (String) Cache.Org.get(accessKey);
                debugInfo.put('accessCacheExists', !String.isBlank(cachedAccess));
                if (!String.isBlank(cachedAccess)) {
                    Map<String, Object> accessData = (Map<String, Object>) JSON.deserializeUntyped(cachedAccess);
                    debugInfo.put('accessExpiresAt', accessData.get('expiresAt'));
                    debugInfo.put('accessLevel', accessData.get('accessLevel'));
                }
                // Check ContactShare records
                if (Schema.SObjectType.ContactShare.isAccessible()) {
                    List<ContactShare> shares = [
                        SELECT Id, ContactAccessLevel, RowCause
                        FROM ContactShare 
                        WHERE ContactId = :tr.contactId 
                        AND UserOrGroupId = :UserInfo.getUserId()
                        LIMIT 5
                    ];
                    List<Map<String, Object>> shareInfo = new List<Map<String, Object>>();
                    for (ContactShare share : shares) {
                        shareInfo.add(new Map<String, Object>{
                            'id' => share.Id,
                            'accessLevel' => share.ContactAccessLevel,
                            'rowCause' => share.RowCause
                        });
                    }
                    debugInfo.put('contactShares', shareInfo);
                }
            }
            // Check if there's a pending email change
            if (tr.valid) {
                String emailChangeKey = ContactPortalCacheUtil.emailChangeCacheKey(tr.contactId);
                String pendingEmailData = (String) Cache.Org.get(emailChangeKey);
                debugInfo.put('pendingEmailChange', !String.isBlank(pendingEmailData));
                if (!String.isBlank(pendingEmailData)) {
                    Map<String, Object> pending = (Map<String, Object>) JSON.deserializeUntyped(pendingEmailData);
                    debugInfo.put('pendingEmail', pending.get('newEmail'));
                    debugInfo.put('emailChangeExpiry', pending.get('expiry'));
                    debugInfo.put('emailChangeAttempts', pending.get('attempts'));
                }
            }
        } catch (Exception e) {
            debugInfo.put('exception', e.getMessage());
            debugInfo.put('stackTrace', e.getStackTraceString());
        }
        return debugInfo;
    }
    
    /**
     * Authenticates a contact using their email and a verification code
     * 
     * @param email The contact's email address
     * @param verificationCode The verification code sent to the contact
     * @return Map<String, Object> Authentication result with token if successful
     */
    @RemoteAction
    public static Map<String, Object> authenticateContact(String email, String verificationCode) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        
        try {
            // Validate inputs
            if (String.isBlank(email) || String.isBlank(verificationCode)) {
                result.put('message', 'Email and verification code are required');
                return result;
            }
            
            // Check verification code
            String cacheKey = ContactPortalCacheUtil.verificationCacheKey(email);
            String cachedData = (String) Cache.Org.get(cacheKey);
            
            if (String.isBlank(cachedData)) {
                result.put('message', 'Verification code expired or not found');
                return result;
            }
            
            Map<String, Object> verificationData = (Map<String, Object>) JSON.deserializeUntyped(cachedData);
            String expectedCode = (String) verificationData.get('code');
            Integer attempts = (Integer) verificationData.get('attempts');
            
            // Increment attempt count
            verificationData.put('attempts', attempts + 1);
            Cache.Org.put(cacheKey, JSON.serialize(verificationData), 300); // 5 minutes
            
            // Check for too many attempts
            if (attempts >= 5) {
                result.put('message', 'Too many failed attempts. Please request a new code.');
                return result;
            }
            
            // Validate code
            if (verificationCode != expectedCode) {
                result.put('message', 'Invalid verification code');
                return result;
            }
            
            // Find the contact
            if (!Schema.SObjectType.Contact.isAccessible()) {
                result.put('message', 'Contact access denied');
                return result;
            }
            
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName 
                FROM Contact 
                WHERE Email = :email 
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                result.put('message', 'No contact found with this email');
                return result;
            }
            
            Contact contact = contacts[0];
            
            // Issue token
            String token = ContactPortalSecurityService.issueSecureToken(contact.Id, email);
            
            // Grant access
            grantContactAccess(contact.Id);
            
            // Clear verification code
            Cache.Org.remove(cacheKey);
            
            // Return success
            result.put('success', true);
            result.put('token', token);
            result.put('contactId', contact.Id);
            result.put('firstName', contact.FirstName);
            result.put('lastName', contact.LastName);
            
            // Log successful authentication
            ContactPortalLogger.logSecurityEvent('AUTHENTICATION_SUCCESS', email, 'Contact authenticated');
            
        } catch (Exception e) {
            result.put('message', 'Authentication error');
            ContactPortalLogger.logError('Authentication error', e);
        }
        
        return result;
    }
    
    /**
     * Grants access to a contact for the current user
     * 
     * @param contactId The ID of the contact to grant access to
     */
    private static void grantContactAccess(Id contactId) {
        try {
            // Create access record in cache
            Long expiresAt = System.currentTimeMillis() + (4 * 60 * 60 * 1000); // 4 hours
            
            Map<String, Object> accessData = new Map<String, Object>{
                'contactId' => contactId,
                'userId' => UserInfo.getUserId(),
                'expiresAt' => expiresAt,
                'accessLevel' => 'Edit'
            };
            
            String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(contactId, UserInfo.getUserId());
            Cache.Org.put(accessKey, JSON.serialize(accessData), 4 * 60 * 60); // 4 hours
            
            // Create ContactShare record if user is authenticated
            if (!UserInfo.getUserType().equals('Guest')) {
                if (Schema.SObjectType.ContactShare.isCreateable()) {
                    // Check if share already exists
                    List<ContactShare> existingShares = [
                        SELECT Id 
                        FROM ContactShare 
                        WHERE ContactId = :contactId 
                        AND UserOrGroupId = :UserInfo.getUserId()
                        AND RowCause = 'Manual'
                        LIMIT 1
                    ];
                    
                    if (existingShares.isEmpty()) {
                        ContactShare share = new ContactShare(
                            ContactId = contactId,
                            UserOrGroupId = UserInfo.getUserId(),
                            ContactAccessLevel = 'Edit',
                            RowCause = 'Manual'
                        );
                        
                        ContactPortalUpdater.insertContactShareWithElevatedAccess(share);
                    }
                }
            }
        } catch (Exception e) {
            ContactPortalLogger.logError('Failed to grant contact access', e);
        }
    }
    
    // Add other methods as needed...
}
