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
            // Get token validation result
            ContactPortalSecurityService.TokenResult tr = 
                ContactPortalSecurityService.validateSecureToken(signedToken);
            
            // Add basic token validation info
            debugInfo.put('tokenValid', tr.valid);
            debugInfo.put('tokenMessage', tr.message);
            
            // Exit early if token is invalid
            if (!tr.valid) {
                return debugInfo;
            }
            
            // Add basic token info
            addBasicTokenInfo(debugInfo, tr);
            
            // Process additional information only if token is valid
            processValidTokenInfo(debugInfo, tr);
            
        } catch (Exception e) {
            debugInfo.put('exception', e.getMessage());
            debugInfo.put('stackTrace', e.getStackTraceString());
        }
        
        return debugInfo;
    }
    
    /**
     * Adds basic token information to the debug info
     */
    private static void addBasicTokenInfo(Map<String, Object> debugInfo, 
                                         ContactPortalSecurityService.TokenResult tr) {
        debugInfo.put('contactId', tr.contactId);
        debugInfo.put('email', tr.verifiedEmail);
        debugInfo.put('issuedAt', tr.issuedAt);
    }
    
    /**
     * Processes additional information for a valid token
     */
    private static void processValidTokenInfo(Map<String, Object> debugInfo, 
                                             ContactPortalSecurityService.TokenResult tr) {
        // Add cache information
        addCacheInfoToDebug(debugInfo, tr);
        
        // Add ContactShare information if accessible
        addShareInfoToDebug(debugInfo, tr.contactId);
        
        // Add pending email change information
        addEmailChangeInfoToDebug(debugInfo, tr.contactId);
    }
    
    /**
     * Helper method to add cache information to debug info
     */
    private static void addCacheInfoToDebug(Map<String, Object> debugInfo, 
                                           ContactPortalSecurityService.TokenResult tr) {
        // Check security context in cache
        String securityKey = ContactPortalSecurityService.getSecurityCacheKey(
            tr.verifiedEmail, tr.contactId);
        String cachedContext = (String) Cache.Org.get(securityKey);
        debugInfo.put('securityContextExists', !String.isBlank(cachedContext));
        
        // Check access permissions
        String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(
            tr.contactId, UserInfo.getUserId());
        String cachedAccess = (String) Cache.Org.get(accessKey);
        debugInfo.put('accessCacheExists', !String.isBlank(cachedAccess));
        
        // Add access details if available
        if (!String.isBlank(cachedAccess)) {
            addAccessDetailsToDebug(debugInfo, cachedAccess);
        }
    }
    
    /**
     * Adds access details from cache to debug info
     */
    private static void addAccessDetailsToDebug(Map<String, Object> debugInfo, String cachedAccess) {
        Map<String, Object> accessData = (Map<String, Object>) JSON.deserializeUntyped(cachedAccess);
        debugInfo.put('accessExpiresAt', accessData.get('expiresAt'));
        debugInfo.put('accessLevel', accessData.get('accessLevel'));
    }
    
    /**
     * Helper method to add ContactShare information to debug info
     */
    private static void addShareInfoToDebug(Map<String, Object> debugInfo, Id contactId) {
        // Explicitly check CRUD permissions right before SOQL
        if (!Schema.SObjectType.ContactShare.isAccessible()) {
            return;
        }
        
        try {
            // Query ContactShare records with security enforced
            List<ContactShare> shares = [
                SELECT Id, ContactAccessLevel, RowCause
                FROM ContactShare 
                WHERE ContactId = :contactId 
                AND UserOrGroupId = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
                LIMIT 5
            ];
            
            // Convert to simplified map for JSON serialization
            List<Map<String, Object>> shareInfo = new List<Map<String, Object>>();
            for (ContactShare share : shares) {
                shareInfo.add(new Map<String, Object>{
                    'id' => share.Id,
                    'accessLevel' => share.ContactAccessLevel,
                    'rowCause' => share.RowCause
                });
            }
            
            debugInfo.put('contactShares', shareInfo);
        } catch (System.QueryException e) {
            // Handle security enforced exceptions
            debugInfo.put('shareQueryError', e.getMessage());
        }
    }
    
    /**
     * Helper method to add pending email change information to debug info
     */
    private static void addEmailChangeInfoToDebug(Map<String, Object> debugInfo, Id contactId) {
        String emailChangeKey = ContactPortalCacheUtil.emailChangeCacheKey(contactId);
        String pendingEmailData = (String) Cache.Org.get(emailChangeKey);
        debugInfo.put('pendingEmailChange', !String.isBlank(pendingEmailData));
        
        if (!String.isBlank(pendingEmailData)) {
            addPendingEmailDetailsToDebug(debugInfo, pendingEmailData);
        }
    }
    
    /**
     * Adds pending email change details to debug info
     */
    private static void addPendingEmailDetailsToDebug(Map<String, Object> debugInfo, 
                                                     String pendingEmailData) {
        Map<String, Object> pending = (Map<String, Object>) JSON.deserializeUntyped(pendingEmailData);
        debugInfo.put('pendingEmail', pending.get('newEmail'));
        debugInfo.put('emailChangeExpiry', pending.get('expiry'));
        debugInfo.put('emailChangeAttempts', pending.get('attempts'));
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
        // Initialize result
        Map<String, Object> result = initializeAuthResult();
        
        try {
            // Validate inputs
            if (!validateAuthInputs(email, verificationCode, result)) {
                return result;
            }
            
            // Process authentication
            processAuthentication(email, verificationCode, result);
            
        } catch (Exception e) {
            handleAuthException(result, e);
        }
        
        return result;
    }
    
    /**
     * Initializes the authentication result map
     */
    private static Map<String, Object> initializeAuthResult() {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        return result;
    }
    
    /**
     * Validates authentication inputs
     */
    private static Boolean validateAuthInputs(String email, String verificationCode, 
                                             Map<String, Object> result) {
        if (String.isBlank(email) || String.isBlank(verificationCode)) {
            result.put('message', 'Email and verification code are required');
            return false;
        }
        return true;
    }
    
    /**
     * Processes the authentication flow
     */
    private static void processAuthentication(String email, String verificationCode, 
                                             Map<String, Object> result) {
        // Validate verification code
        Map<String, Object> verificationResult = validateVerificationCode(email, verificationCode);
        if (!(Boolean)verificationResult.get('valid')) {
            result.put('message', verificationResult.get('message'));
            return;
        }
        
        // Find and authenticate the contact
        Contact contact = findContactByEmail(email);
        if (contact == null) {
            result.put('message', 'No contact found with this email');
            return;
        }
        
        // Complete authentication
        completeAuthentication(email, contact, result);
    }
    
    /**
     * Completes the authentication process after verification
     */
    private static void completeAuthentication(String email, Contact contact, 
                                              Map<String, Object> result) {
        // Issue token and grant access
        String token = ContactPortalSecurityService.issueSecureToken(contact.Id, email);
        grantContactAccess(contact.Id);
        
        // Clear verification code
        String cacheKey = ContactPortalCacheUtil.verificationCacheKey(email);
        Cache.Org.remove(cacheKey);
        
        // Set success result
        setSuccessResult(result, token, contact);
        
        // Log successful authentication
        ContactPortalLogger.logSecurityEvent('AUTHENTICATION_SUCCESS', email, 'Contact authenticated');
    }
    
    /**
     * Sets the success result with contact information
     */
    private static void setSuccessResult(Map<String, Object> result, String token, Contact contact) {
        result.put('success', true);
        result.put('token', token);
        result.put('contactId', contact.Id);
        result.put('firstName', contact.FirstName);
        result.put('lastName', contact.LastName);
    }
    
    /**
     * Handles authentication exceptions
     */
    private static void handleAuthException(Map<String, Object> result, Exception e) {
        result.put('message', 'Authentication error');
        ContactPortalLogger.logError('Authentication error', e);
    }

    /**
     * Validates a verification code for an email
     * 
     * @param email The email address
     * @param verificationCode The verification code to validate
     * @return Map<String, Object> Validation result
     */
    private static Map<String, Object> validateVerificationCode(String email, String verificationCode) {
        // Initialize result
        Map<String, Object> result = new Map<String, Object>{
            'valid' => false,
            'message' => ''
        };
        
        // Get verification data from cache
        String cacheKey = ContactPortalCacheUtil.verificationCacheKey(email);
        String cachedData = (String) Cache.Org.get(cacheKey);
        
        // Check if verification data exists
        if (String.isBlank(cachedData)) {
            result.put('message', 'Verification code expired or not found');
            return result;
        }
        
        // Process verification data
        return processVerificationData(email, verificationCode, cachedData, cacheKey);
    }
    
    /**
     * Processes verification data from cache
     */
    private static Map<String, Object> processVerificationData(String email, String verificationCode, 
                                                              String cachedData, String cacheKey) {
        Map<String, Object> result = new Map<String, Object>{
            'valid' => false,
            'message' => ''
        };
        
        // Parse verification data
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
        
        // Code is valid
        result.put('valid', true);
        return result;
    }
    
    /**
     * Finds a contact by email address
     * 
     * @param email The email address to search for
     * @return Contact The found contact or null
     */
    private static Contact findContactByEmail(String email) {
        // CRUD check immediately before SOQL
        if (!Schema.SObjectType.Contact.isAccessible()) {
            ContactPortalLogger.logSecurityEvent('CRUD_PERMISSION_ERROR', 
                email, 'No read access to Contact object');
            return null;
        }
        
        try {
            // Query with security enforced
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName 
                FROM Contact 
                WHERE Email = :email 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            return contacts.isEmpty() ? null : contacts[0];
        } catch (System.QueryException e) {
            ContactPortalLogger.logError('Error querying contact', e);
            return null;
        }
    }
    
    /**
     * Grants access to a contact for the current user
     * 
     * @param contactId The ID of the contact to grant access to
     */
    private static void grantContactAccess(Id contactId) {
        try {
            // Create access record in cache
            createAccessCacheRecord(contactId);
            
            // Create ContactShare record if user is authenticated
            if (!UserInfo.getUserType().equals('Guest')) {
                createContactShareRecord(contactId);
            }
        } catch (Exception e) {
            ContactPortalLogger.logError('Failed to grant contact access', e);
        }
    }
    
    /**
     * Creates an access cache record for the current user
     * 
     * @param contactId The contact ID to grant access to
     */
    private static void createAccessCacheRecord(Id contactId) {
        // Calculate expiration time (4 hours from now)
        Long expiresAt = System.currentTimeMillis() + (4 * 60 * 60 * 1000);
        
        // Create access data
        Map<String, Object> accessData = new Map<String, Object>{
            'contactId' => contactId,
            'userId' => UserInfo.getUserId(),
            'expiresAt' => expiresAt,
            'accessLevel' => 'Edit'
        };
        
        // Store in cache
        String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(contactId, UserInfo.getUserId());
        Cache.Org.put(accessKey, JSON.serialize(accessData), 4 * 60 * 60);
    }
    
    /**
     * Creates a ContactShare record if one doesn't already exist
     * 
     * @param contactId The contact ID to share
     */
    private static void createContactShareRecord(Id contactId) {
        // Exit if no create permission
        if (!Schema.SObjectType.ContactShare.isCreateable()) {
            return;
        }
        
        // Exit if no read permission
        if (!Schema.SObjectType.ContactShare.isAccessible()) {
            return;
        }
        
        try {
            // Check if share already exists
            List<ContactShare> existingShares = [
                SELECT Id 
                FROM ContactShare 
                WHERE ContactId = :contactId 
                AND UserOrGroupId = :UserInfo.getUserId()
                AND RowCause = 'Manual'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            // Create new share if needed
            if (existingShares.isEmpty()) {
                insertNewContactShare(contactId);
            }
        } catch (System.QueryException e) {
            ContactPortalLogger.logError('Error checking existing shares', e);
        }
    }
    
    /**
     * Inserts a new ContactShare record
     */
    private static void insertNewContactShare(Id contactId) {
        ContactShare share = new ContactShare(
            ContactId = contactId,
            UserOrGroupId = UserInfo.getUserId(),
            ContactAccessLevel = 'Edit',
            RowCause = 'Manual'
        );
        
        ContactPortalUpdater.insertContactShareWithElevatedAccess(share);
    }
}