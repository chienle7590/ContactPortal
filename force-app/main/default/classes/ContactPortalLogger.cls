/**
 * Utility class for logging in the Contact Portal
 */
public with sharing class ContactPortalLogger {
    
    /**
     * Logs an error message
     * 
     * @param msg The error message
     * @param e The exception
     */
    public static void logError(String msg, Exception e) {
        System.debug(LoggingLevel.ERROR, 
            '[ERROR] ' + msg + ' | ' + e.getMessage() + ' | ' + e.getStackTraceString()
        );
    }
    
    /**
     * Logs a security event
     * 
     * @param event The security event
     * @param email The email address associated with the event
     * @param details Additional details about the event
     */
    public static void logSecurityEvent(String event, String email, String details) {
        System.debug(LoggingLevel.WARN, 
            '[SECURITY_EVENT] ' + event + ' | Email: ' + email + ' | Details: ' + details + 
            ' | User: ' + UserInfo.getUserId() + ' | IP: ' + getClientIP()
        );
        // TODO: Consider writing to custom Security_Log__c object for audit trail
    }
    
    /**
     * Gets the client IP address
     * 
     * @return String The client IP address
     */
    private static String getClientIP() {
        return ApexPages.currentPage()?.getHeaders()?.get('X-Forwarded-For') ?? 'Unknown';
    }
}