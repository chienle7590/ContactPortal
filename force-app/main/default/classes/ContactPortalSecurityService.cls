/**
 * Service class for security-related operations in the Contact Portal
 */
public with sharing class ContactPortalSecurityService {
    
    private static final Integer TOKEN_TTL_MINUTES = 60; // 1 hour
    private static final String VERIFIED_ACCESS_PREFIX = 'VerifiedAccess';
    
    // =============================
    // SECURITY CLASSES
    // =============================
    public class SecurityContext {
        public String verifiedEmail;
        public Id contactId;
        public Long verificationTime;
        public String sessionId;
    }
    
    public class AccessValidationResult {
        public Boolean isValid = false;
        public String errorMessage;
        public SecurityContext context;
    }
    
    public class TokenResult {
        public Boolean valid = false;
        public String message;
        public Id contactId;
        public String verifiedEmail;
        public Long issuedAt;
    }
    
    /**
     * Issues a secure token for a contact
     * 
     * @param contactId The contact ID
     * @param verifiedEmail The verified email address
     * @return String The secure token
     */
    public static String issueSecureToken(Id contactId, String verifiedEmail) {
        Long now = System.currentTimeMillis();
        Long expiry = now + (TOKEN_TTL_MINUTES * 60L * 1000L);
        String sessionId = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);
        
        String core = contactId + '|' + verifiedEmail + '|' + String.valueOf(expiry) + '|' + String.valueOf(now) + '|' + sessionId;
        String sig = sign(core);
        
        // Store security context in cache
        SecurityContext ctx = new SecurityContext();
        ctx.verifiedEmail = verifiedEmail;
        ctx.contactId = contactId;
        ctx.verificationTime = now;
        ctx.sessionId = sessionId;
        
        String securityKey = getSecurityCacheKey(verifiedEmail, contactId);
        Cache.Org.put(securityKey, JSON.serialize(ctx), TOKEN_TTL_MINUTES * 60);
        
        return EncodingUtil.base64Encode(Blob.valueOf(core + '|' + sig));
    }
    
    /**
     * Validates a secure token
     * 
     * @param token The token to validate
     * @return TokenResult The validation result
     */
    public static TokenResult validateSecureToken(String token) {
        TokenResult tr = new TokenResult();
        try {
            if (String.isBlank(token)) { 
                tr.message = 'Missing authentication token'; 
                return tr; 
            }
            
            String decoded = EncodingUtil.base64Decode(token).toString();
            List<String> parts = decoded.split('\\|');
            if (parts.size() != 6) { 
                tr.message = 'Invalid token format'; 
                return tr; 
            }
            
            String cid = parts[0];
            String email = parts[1];
            Long expiry = Long.valueOf(parts[2]);
            Long issuedAt = Long.valueOf(parts[3]);
            String sessionId = parts[4];
            String sig = parts[5];
            
            // Verify signature
            String expectedSig = sign(cid + '|' + email + '|' + parts[2] + '|' + parts[3] + '|' + sessionId);
            if (expectedSig != sig) { 
                ContactPortalLogger.logSecurityEvent('INVALID_TOKEN_SIGNATURE', email, 'Token signature mismatch');
                tr.message = 'Invalid token signature'; 
                return tr; 
            }
            
            // Check expiry
            if (System.currentTimeMillis() > expiry) { 
                ContactPortalLogger.logSecurityEvent('EXPIRED_TOKEN', email, 'Token expired');
                tr.message = 'Session expired'; 
                return tr; 
            }
            
            // Validate security context still exists
            String securityKey = getSecurityCacheKey(email, (Id)cid);
            String cachedContext = (String) Cache.Org.get(securityKey);
            if (String.isBlank(cachedContext)) {
                ContactPortalLogger.logSecurityEvent('MISSING_SECURITY_CONTEXT', email, 'Security context not found');
                tr.message = 'Security context expired';
                return tr;
            }
            
            SecurityContext ctx = (SecurityContext) JSON.deserialize(cachedContext, SecurityContext.class);
            if (ctx.sessionId != sessionId || ctx.verificationTime != issuedAt) {
                ContactPortalLogger.logSecurityEvent('SECURITY_CONTEXT_MISMATCH', email, 'Context validation failed');
                tr.message = 'Security validation failed';
                return tr;
            }
            
            tr.contactId = (Id) cid;
            tr.verifiedEmail = email;
            tr.issuedAt = issuedAt;
            tr.valid = true;
            
        } catch (Exception e) {
            ContactPortalLogger.logSecurityEvent('TOKEN_VALIDATION_ERROR', 'unknown', e.getMessage());
            tr.message = 'Token validation error';
        }
        return tr;
    }
    
    /**
     * Validates contact access for an operation
     * 
     * @param token The secure token
     * @param operation The operation being performed
     * @return AccessValidationResult The validation result
     */
    public static AccessValidationResult validateContactAccess(String token, String operation) {
        System.debug('🔍 Validating access for operation: ' + operation);
        AccessValidationResult result = new AccessValidationResult();
        
        // Validate token
        TokenResult tr = validateSecureToken(token);
        if (!tr.valid) {
            result.errorMessage = tr.message;
            return result;
        }
        
        // Verify contact exists and email matches
        if (!verifyContactExists(tr, result)) {
            return result;
        }
        
        // Check access permissions
        if (!checkAccessPermissions(tr, operation, result)) {
            return result;
        }
        
        // Set up security context
        SecurityContext ctx = new SecurityContext();
        ctx.verifiedEmail = tr.verifiedEmail;
        ctx.contactId = tr.contactId;
        ctx.verificationTime = tr.issuedAt;
        
        result.context = ctx;
        result.isValid = true;
        
        ContactPortalLogger.logSecurityEvent('ACCESS_VALIDATED', tr.verifiedEmail, 'Operation: ' + operation);
        
        return result;
    }
    
    /**
     * Verifies that a contact exists and matches the email
     * 
     * @param tr The token result
     * @param result The access validation result to update
     * @return Boolean True if the contact exists and matches
     */
    private static boolean verifyContactExists(TokenResult tr, AccessValidationResult result) {
        try {
            // CRUD permission check
            if (!Schema.SObjectType.Contact.isAccessible()) {
                ContactPortalLogger.logSecurityEvent('CRUD_PERMISSION_ERROR', tr.verifiedEmail, 'No read access to Contact object');
                result.errorMessage = 'Insufficient permissions to access contact data.';
                return false;
            }
            
            List<Contact> contacts = [
                SELECT Id, Email, LastModifiedDate
                FROM Contact 
                WHERE Id = :tr.contactId 
                AND Email = :tr.verifiedEmail 
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                ContactPortalLogger.logSecurityEvent('CONTACT_VALIDATION_FAILED', tr.verifiedEmail, 'Contact not found or email changed');
                result.errorMessage = 'Contact access validation failed';
                return false;
            }
            
            // Check if contact was modified by someone else recently (potential security issue)
            if (contacts[0].LastModifiedDate.getTime() > tr.issuedAt && 
                contacts[0].LastModifiedDate.getTime() > (System.currentTimeMillis() - 60000)) { // 1 minute grace period
                
                ContactPortalLogger.logSecurityEvent('CONCURRENT_MODIFICATION_DETECTED', tr.verifiedEmail, 
                    'Contact modified after token issued - potential security breach');
                result.errorMessage = 'Contact was recently modified. Please re-verify for security.';
                return false;
            }
            
            return true;
        } catch (Exception e) {
            ContactPortalLogger.logError('Contact existence validation failed', e);
            result.errorMessage = 'Error validating contact';
            return false;
        }
    }
    
    /**
     * Checks access permissions for an operation
     * 
     * @param tr The token result
     * @param operation The operation being performed
     * @param result The access validation result to update
     * @return Boolean True if access is permitted
     */
    private static boolean checkAccessPermissions(TokenResult tr, String operation, AccessValidationResult result) {
        try {
            // Check cache-based access first with proper key
            String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(tr.contactId, UserInfo.getUserId());
            String cachedAccess = (String) Cache.Org.get(accessKey);
            
            boolean hasValidAccess = false;
            
            if (String.isNotBlank(cachedAccess)) {
                hasValidAccess = validateCachedAccess(cachedAccess, tr, operation);
            }
            
            // If no valid cache access, check ContactShare (for authenticated users)
            if (!hasValidAccess) {
                hasValidAccess = validateContactShareAccess(tr, operation, result);
            }
            
            if (!hasValidAccess) {
                ContactPortalLogger.logSecurityEvent('ACCESS_DENIED', tr.verifiedEmail, 'No valid access found for operation: ' + operation);
                result.errorMessage = 'Access denied.';
                return false;
            }
            
            return true;
        } catch (Exception e) {
            ContactPortalLogger.logError('Access permission check failed', e);
            result.errorMessage = 'Error checking access permissions';
            return false;
        }
    }
    
    /**
     * Validates cached access for an operation
     * 
     * @param cachedAccess The cached access data
     * @param tr The token result
     * @param operation The operation being performed
     * @return Boolean True if access is valid
     */
    private static boolean validateCachedAccess(String cachedAccess, TokenResult tr, String operation) {
        try {
            Map<String, Object> accessData = (Map<String, Object>) JSON.deserializeUntyped(cachedAccess);
            Long expiresAt = (Long) accessData.get('expiresAt');
            String cachedEmail = (String) accessData.get('verifiedEmail');
            String accessLevel = (String) accessData.get('accessLevel');
            
            if (System.now().getTime() < expiresAt && 
                cachedEmail == tr.verifiedEmail && 
                (operation != 'UPDATE' || accessLevel == 'Edit')) {
                
                System.debug('✅ Cache-based access validated');
                return true;
            } else {
                System.debug('⚠️ Cache-based access expired or insufficient permissions');
                return false;
            }
        } catch (Exception e) {
            System.debug('⚠️ Failed to parse cached access data: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Validates ContactShare access for a contact
     * 
     * @param tr The token result
     * @param operation The operation being performed
     * @param result The access validation result to update
     * @return Boolean True if access is valid
     */
    private static boolean validateContactShareAccess(TokenResult tr, String operation, AccessValidationResult result) {
        try {
            // CRUD permission check
            if (!Schema.SObjectType.ContactShare.isAccessible()) {
                return checkContactOwnership(tr);
            }
            
            List<ContactShare> shares = [
                SELECT Id, ContactAccessLevel 
                FROM ContactShare 
                WHERE ContactId = :tr.contactId 
                AND UserOrGroupId = :UserInfo.getUserId() 
                AND (RowCause = 'Manual' OR RowCause = 'Owner')
                LIMIT 1
            ];
            
            if (!shares.isEmpty()) {
                if (operation == 'UPDATE' && shares[0].ContactAccessLevel == 'Read') {
                    result.errorMessage = 'Insufficient permissions for update.';
                    return false;
                }
                System.debug('✅ ContactShare access validated');
                return true;
            }
            
            return checkContactOwnership(tr);
        } catch (Exception e) {
            System.debug('⚠️ Error checking ContactShare access: ' + e.getMessage());
            return checkContactOwnership(tr);
        }
    }
    
    /**
     * Checks if the current user is the owner of the contact
     * 
     * @param tr The token result
     * @return Boolean True if the user is the owner
     */
    private static boolean checkContactOwnership(TokenResult tr) {
        try {
            // CRUD permission check
            if (!Schema.SObjectType.Contact.isAccessible()) {
                return false;
            }
            
            List<Contact> ownedContacts = [
                SELECT Id FROM Contact 
                WHERE Id = :tr.contactId AND OwnerId = :UserInfo.getUserId() 
                LIMIT 1
            ];
            
            if (!ownedContacts.isEmpty()) {
                System.debug('✅ Owner access validated');
                return true;
            }
            
            return false;
        } catch (Exception e) {
            System.debug('⚠️ Error checking contact ownership: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Generates a security cache key for a contact and email
     * 
     * @param email The email address
     * @param contactId The contact ID
     * @return String The cache key
     */
    public static String getSecurityCacheKey(String email, Id contactId) {
        return VERIFIED_ACCESS_PREFIX + email.replaceAll('[^a-zA-Z0-9]', '') + String.valueOf(contactId).substring(0, 15);
    }
    
    /**
     * Signs a value using HMAC-SHA256
     * 
     * @param value The value to sign
     * @return String The signature
     */
    private static String sign(String value) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(value), Blob.valueOf(secretKey()));
        return EncodingUtil.convertToHex(mac);
    }
    
    /**
     * Returns the secret key for signing tokens
     * 
     * @return String The secret key
     */
    private static String secretKey() {
        // TODO: Move to Protected Custom Metadata or Named Credential
        return 'REPLACE_WITH_LONG_RANDOM_SECRET_64_CHARS_MINIMUM_LENGTH_FOR_SECURITY';
    }
}