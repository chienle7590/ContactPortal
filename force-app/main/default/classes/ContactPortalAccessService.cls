/**
 * Service class for handling access control in the Contact Portal
 */
public with sharing class ContactPortalAccessService {
    
    /**
     * Grants temporary access to a contact
     * 
     * @param contactId The contact ID
     * @param verifiedEmail The verified email address
     */
    public static void grantTemporaryContactAccess(Id contactId, String verifiedEmail) {
        System.debug('🔍 Granting temporary access for contact: ' + contactId + ', email: ' + verifiedEmail);
        
        try {
            // First verify this is actually the contact's email
            // CRUD permission check
            if (!Schema.SObjectType.Contact.isAccessible()) {
                ContactPortalLogger.logSecurityEvent('CRUD_PERMISSION_ERROR', verifiedEmail, 'No read access to Contact object');
                return;
            }
            
            List<Contact> contacts = [
                SELECT Id, Email 
                FROM Contact 
                WHERE Id = :contactId AND Email = :verifiedEmail 
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                ContactPortalLogger.logSecurityEvent('UNAUTHORIZED_ACCESS_ATTEMPT', verifiedEmail, 'Email mismatch for contact: ' + contactId);
                return;
            }
            
            // For Site Guest Users, we can't create ContactShare records
            // Check user type and handle accordingly
            String userType = UserInfo.getUserType();
            System.debug('🔍 User type: ' + userType + ', Username: ' + UserInfo.getUserName());
            
            if (userType == 'Guest' || Site.isValidUsername(UserInfo.getUserName())) {
                useContactAccessCache(contactId, verifiedEmail);
                return;
            }
            
            // For authenticated users, try to create ContactShare
            grantShareAccess(contactId, verifiedEmail);
            
        } catch (Exception e) {
            System.debug('❌ Exception in grantTemporaryContactAccess: ' + e.getMessage());
            ContactPortalLogger.logError('Failed to grant contact access', e);
            ContactPortalLogger.logSecurityEvent('ACCESS_GRANT_FAILED', verifiedEmail, e.getMessage());
            
            // Final fallback with proper cache key
            useContactAccessCache(contactId, verifiedEmail);
        }
    }
    
    /**
     * Grants access using ContactShare records
     * 
     * @param contactId The contact ID
     * @param verifiedEmail The verified email address
     */
    private static void grantShareAccess(Id contactId, String verifiedEmail) {
        // CRUD permission check
        if (!Schema.SObjectType.ContactShare.isAccessible()) {
            ContactPortalLogger.logSecurityEvent('CRUD_PERMISSION_ERROR', verifiedEmail, 'No read access to ContactShare object');
            // Fall back to cache-based access
            useContactAccessCache(contactId, verifiedEmail);
            return;
        }
        
        List<ContactShare> existingShares = [
            SELECT Id, ContactAccessLevel
            FROM ContactShare 
            WHERE ContactId = :contactId 
            AND UserOrGroupId = :UserInfo.getUserId()
            AND RowCause = 'Manual'
            LIMIT 1
        ];
        
        if (existingShares.isEmpty()) {
            createNewContactShare(contactId, verifiedEmail);
        } else if (existingShares[0].ContactAccessLevel != 'Edit') {
            updateExistingContactShare(existingShares[0], verifiedEmail);
        } else {
            System.debug('✅ ContactShare already exists with Edit access');
        }
    }
    
    /**
     * Creates a new ContactShare record
     * 
     * @param contactId The contact ID
     * @param verifiedEmail The verified email address
     */
    private static void createNewContactShare(Id contactId, String verifiedEmail) {
        try {
            // CRUD permission check
            if (!Schema.SObjectType.ContactShare.isCreateable()) {
                ContactPortalLogger.logSecurityEvent('CRUD_PERMISSION_ERROR', verifiedEmail, 'No create access to ContactShare object');
                // Fall back to cache-based access
                useContactAccessCache(contactId, verifiedEmail);
                return;
            }
            
            ContactShare contactShare = new ContactShare();
            contactShare.ContactId = contactId;
            contactShare.UserOrGroupId = UserInfo.getUserId();
            contactShare.ContactAccessLevel = 'Edit';
            contactShare.RowCause = 'Manual';
            
            // Use ContactPortalUpdater for elevated DML
            ContactPortalUpdater.insertContactShareWithElevatedAccess(contactShare);
            System.debug('✅ ContactShare created successfully');
            ContactPortalLogger.logSecurityEvent('ACCESS_GRANTED', verifiedEmail, 'Edit access granted to contact: ' + contactId);
            
        } catch (Exception shareEx) {
            System.debug('⚠️ ContactShare creation failed: ' + shareEx.getMessage());
            // Fallback to cache-based access
            useContactAccessCache(contactId, verifiedEmail);
        }
    }
    
    /**
     * Updates an existing ContactShare record
     * 
     * @param share The ContactShare record to update
     * @param verifiedEmail The verified email address
     */
    private static void updateExistingContactShare(ContactShare share, String verifiedEmail) {
        try {
            // CRUD permission check
            if (!Schema.SObjectType.ContactShare.isUpdateable()) {
                ContactPortalLogger.logSecurityEvent('CRUD_PERMISSION_ERROR', verifiedEmail, 'No update access to ContactShare object');
                // Fall back to cache-based access
                useContactAccessCache(share.ContactId, verifiedEmail);
                return;
            }
            
            share.ContactAccessLevel = 'Edit';
            // Use ContactPortalUpdater for elevated DML
            ContactPortalUpdater.updateContactShareWithElevatedAccess(share);
            System.debug('✅ ContactShare access level upgraded to Edit');
            ContactPortalLogger.logSecurityEvent('ACCESS_UPGRADED', verifiedEmail, 'Access upgraded to Edit for contact: ' + share.ContactId);
        } catch (Exception upgradeEx) {
            System.debug('⚠️ Failed to upgrade ContactShare: ' + upgradeEx.getMessage());
            ContactPortalLogger.logSecurityEvent('ACCESS_UPGRADE_FAILED', verifiedEmail, upgradeEx.getMessage());
            // Fall back to cache-based access
            useContactAccessCache(share.ContactId, verifiedEmail);
        }
    }
    
    /**
     * Uses cache-based access for a contact
     * 
     * @param contactId The contact ID
     * @param verifiedEmail The verified email address
     */
    public static void useContactAccessCache(Id contactId, String verifiedEmail) {
        try {
            String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(contactId, UserInfo.getUserId());
            Map<String, Object> accessData = new Map<String, Object>{
                'contactId' => contactId,
                'verifiedEmail' => verifiedEmail,
                'grantedAt' => System.now().getTime(),
                'expiresAt' => System.now().addHours(2).getTime(),
                'accessLevel' => 'Edit'
            };
            Cache.Org.put(accessKey, JSON.serialize(accessData), 7200);
            System.debug('✅ Cache-based access granted with key: ' + accessKey);
            ContactPortalLogger.logSecurityEvent('CACHE_ACCESS_GRANTED', verifiedEmail, 'Cache-based edit access granted to contact: ' + contactId);
        } catch (Exception cacheEx) {
            System.debug('❌ Even cache fallback failed: ' + cacheEx.getMessage());
        }
    }
    
    /**
     * Revokes access to a contact
     * 
     * @param contactId The contact ID
     */
    public static void revokeContactAccess(Id contactId) {
        try {
            // Revoke ContactShare access
            // CRUD permission check
            if (Schema.SObjectType.ContactShare.isAccessible() && Schema.SObjectType.ContactShare.isDeletable()) {
                List<ContactShare> shares = [
                    SELECT Id 
                    FROM ContactShare 
                    WHERE ContactId = :contactId 
                    AND UserOrGroupId = :UserInfo.getUserId()
                    AND RowCause = 'Manual'
                ];
                
                if (!shares.isEmpty()) {
                    // Use ContactPortalUpdater for elevated DML
                    ContactPortalUpdater.deleteContactSharesWithElevatedAccess(shares);
                    ContactPortalLogger.logSecurityEvent('ACCESS_REVOKED', 'system', 'ContactShare access revoked for contact: ' + contactId);
                }
            }
            
            // Also revoke cache-based access with proper key
            String accessKey = ContactPortalCacheUtil.generateAccessCacheKey(contactId, UserInfo.getUserId());
            Cache.Org.remove(accessKey);
            System.debug('✅ Cache-based access revoked with key: ' + accessKey);
            
        } catch (Exception e) {
            ContactPortalLogger.logError('Failed to revoke contact access', e);
        }
    }
}