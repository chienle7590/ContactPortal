public with sharing class ContactPortalController {
  
  // Cache duration: 10 minutes
  private static final Integer CACHE_DURATION = 600;
  
  /**
   * Send verification code to contact's email
   * @param email Contact's email address
   * @return Map with success status and message
   */
  @AuraEnabled
  public static Map<String, Object> sendVerificationCode(String email) {
      Map<String, Object> result = new Map<String, Object>();
      
      try {
          // Validate email format
          if (String.isBlank(email) || !isValidEmail(email)) {
              result.put('success', false);
              result.put('message', 'Please enter a valid email address.');
              return result;
          }
          
          // Check if contact exists with this email
          List<Contact> contacts = [
              SELECT Id, Name, Email, Phone, Account.Name 
              FROM Contact 
              WHERE Email = :email.toLowerCase().trim() 
              WITH SECURITY_ENFORCED
              LIMIT 1
          ];
          
          if (contacts.isEmpty()) {
              result.put('success', false);
              result.put('message', 'No contact found with this email address.');
              return result;
          }
          
          // Generate 6-digit verification code
          String verificationCode = generateVerificationCode();
          
          // Store verification code in cache with expiry
          String cacheKey = getCacheKey(email);
          Map<String, Object> cacheData = new Map<String, Object>{
              'code' => verificationCode,
              'contactId' => contacts[0].Id,
              'expiryTime' => System.now().addMinutes(10).getTime()
          };
          
          // Store in org cache for 10 minutes
          Cache.Org.put(cacheKey, JSON.serialize(cacheData), CACHE_DURATION);
          
          // Send email with verification code
          Boolean emailSent = sendVerificationEmail(email, contacts[0].Name, verificationCode);
          
          if (emailSent) {
              result.put('success', true);
              result.put('message', 'Verification code sent to your email address.');
          } else {
              result.put('success', false);
              result.put('message', 'Failed to send verification email. Please try again.');
          }
          
      } catch (QueryException e) {
          System.debug('Query Exception: ' + e.getMessage());
          result.put('success', false);
          result.put('message', 'Unable to access contact information. Please contact support.');
      } catch (Exception e) {
          System.debug('Exception in sendVerificationCode: ' + e.getMessage());
          System.debug('Stack trace: ' + e.getStackTraceString());
          result.put('success', false);
          result.put('message', 'An unexpected error occurred. Please try again.');
      }
      
      return result;
  }
  
  /**
   * Verify code and return contact information
   * @param email Contact's email address
   * @param code Verification code entered by user
   * @return Map with contact information or error
   */
  @AuraEnabled
  public static Map<String, Object> verifyAndGetContact(String email, String code) {
      Map<String, Object> result = new Map<String, Object>();
      
      try {
          // Validate inputs
          if (String.isBlank(email) || String.isBlank(code)) {
              result.put('success', false);
              result.put('message', 'Email and verification code are required.');
              return result;
          }
          
          // Get cached verification data
          String cacheKey = getCacheKey(email);
          String cachedDataJson = (String) Cache.Org.get(cacheKey);
          
          if (String.isBlank(cachedDataJson)) {
              result.put('success', false);
              result.put('message', 'Verification code has expired. Please request a new one.');
              return result;
          }
          
          // Parse cached data
          Map<String, Object> cachedData = (Map<String, Object>) JSON.deserializeUntyped(cachedDataJson);
          String storedCode = (String) cachedData.get('code');
          String contactId = (String) cachedData.get('contactId');
          Long expiryTime = (Long) cachedData.get('expiryTime');
          
          // Check if code has expired
          if (System.now().getTime() > expiryTime) {
              // Remove expired cache
              Cache.Org.remove(cacheKey);
              result.put('success', false);
              result.put('message', 'Verification code has expired. Please request a new one.');
              return result;
          }
          
          // Verify the code
          if (!code.equals(storedCode)) {
              result.put('success', false);
              result.put('message', 'Invalid verification code. Please try again.');
              return result;
          }
          
          // Get contact information
          List<Contact> contacts = [
              SELECT Id, Name, FirstName, LastName, Email, Phone, 
                     MobilePhone, Title, Account.Name, Account.Website,
                     MailingStreet, MailingCity, MailingState, 
                     MailingPostalCode, MailingCountry
              FROM Contact 
              WHERE Id = :contactId 
              WITH SECURITY_ENFORCED
              LIMIT 1
          ];
          
          if (contacts.isEmpty()) {
              result.put('success', false);
              result.put('message', 'Contact not found.');
              return result;
          }
          
          Contact contact = contacts[0];
          
          // Prepare contact data for return
          Map<String, Object> contactData = new Map<String, Object>{
              'Id' => contact.Id,
              'Name' => contact.Name,
              'FirstName' => contact.FirstName,
              'LastName' => contact.LastName,
              'Email' => contact.Email,
              'Phone' => contact.Phone,
              'MobilePhone' => contact.MobilePhone,
              'Title' => contact.Title,
              'AccountName' => contact.Account?.Name,
              'AccountWebsite' => contact.Account?.Website,
              'MailingAddress' => formatMailingAddress(contact)
          };
          
          // Remove verification code from cache (one-time use)
          Cache.Org.remove(cacheKey);
          
          result.put('success', true);
          result.put('contact', contactData);
          result.put('message', 'Verification successful.');
          
      } catch (QueryException e) {
          System.debug('Query Exception: ' + e.getMessage());
          result.put('success', false);
          result.put('message', 'Unable to access contact information. Please contact support.');
      } catch (Exception e) {
          System.debug('Exception in verifyAndGetContact: ' + e.getMessage());
          System.debug('Stack trace: ' + e.getStackTraceString());
          result.put('success', false);
          result.put('message', 'An unexpected error occurred. Please try again.');
      }
      
      return result;
  }
  
  /**
   * Generate a 6-digit verification code
   * @return String verification code
   */
  private static String generateVerificationCode() {
      Integer code = Math.mod(Math.abs(Crypto.getRandomInteger()), 900000) + 100000;
      return String.valueOf(code);
  }
  
  /**
   * Generate cache key for email
   * @param email Email address
   * @return String cache key
   */
  private static String getCacheKey(String email) {
      // Remove special characters and make lowercase for consistent cache key
      String cleanEmail = email.toLowerCase().replaceAll('[^a-zA-Z0-9]', '');
      return 'VerificationCode' + cleanEmail;
  }
  
  /**
   * Validate email format
   * @param email Email to validate
   * @return Boolean true if valid
   */
  private static Boolean isValidEmail(String email) {
      String emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
      Pattern emailPattern = Pattern.compile(emailRegex);
      return emailPattern.matcher(email).matches();
  }
  
  /**
   * Format mailing address
   * @param contact Contact record
   * @return String formatted address
   */
  private static String formatMailingAddress(Contact contact) {
      List<String> addressParts = new List<String>();
      
      if (String.isNotBlank(contact.MailingStreet)) {
          addressParts.add(contact.MailingStreet);
      }
      
      List<String> cityStateZip = new List<String>();
      if (String.isNotBlank(contact.MailingCity)) {
          cityStateZip.add(contact.MailingCity);
      }
      if (String.isNotBlank(contact.MailingState)) {
          cityStateZip.add(contact.MailingState);
      }
      if (String.isNotBlank(contact.MailingPostalCode)) {
          cityStateZip.add(contact.MailingPostalCode);
      }
      
      if (!cityStateZip.isEmpty()) {
          addressParts.add(String.join(cityStateZip, ', '));
      }
      
      if (String.isNotBlank(contact.MailingCountry)) {
          addressParts.add(contact.MailingCountry);
      }
      
      return addressParts.isEmpty() ? 'No address on file' : String.join(addressParts, '\n');
  }
  
  /**
   * Send verification email to contact
   * @param email Recipient email
   * @param contactName Contact name
   * @param verificationCode Code to send
   * @return Boolean success status
   */
  private static Boolean sendVerificationEmail(String email, String contactName, String verificationCode) {
      try {
          // Create email message
          Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
          emailMessage.setToAddresses(new String[] { email });
          emailMessage.setSubject('Your Contact Portal Verification Code');
          
          // Email body
          String emailBody = 'Dear ' + contactName + ',\n\n';
          emailBody += 'Your verification code for the Contact Portal is: ' + verificationCode + '\n\n';
          emailBody += 'This code will expire in 10 minutes.\n\n';
          emailBody += 'If you did not request this code, please ignore this email.\n\n';
          emailBody += 'Best regards,\n';
          emailBody += 'Contact Portal Team';
          
          emailMessage.setPlainTextBody(emailBody);
          
          // HTML version
          String htmlBody = '<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">';
          htmlBody += '<h2 style="color: #1589ee;">Contact Portal Verification</h2>';
          htmlBody += '<p>Dear ' + contactName + ',</p>';
          htmlBody += '<p>Your verification code for the Contact Portal is:</p>';
          htmlBody += '<div style="background: #f4f4f4; padding: 20px; text-align: center; font-size: 24px; font-weight: bold; color: #1589ee; border-radius: 5px; margin: 20px 0;">';
          htmlBody += verificationCode;
          htmlBody += '</div>';
          htmlBody += '<p><strong>This code will expire in 10 minutes.</strong></p>';
          htmlBody += '<p>If you did not request this code, please ignore this email.</p>';
          htmlBody += '<p>Best regards,<br/>Contact Portal Team</p>';
          htmlBody += '</div>';
          
          emailMessage.setHtmlBody(htmlBody);
          
          // Send email
          Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { emailMessage });
          
          return results[0].isSuccess();
          
      } catch (Exception e) {
          System.debug('Email sending exception: ' + e.getMessage());
          return false;
      }
  }
}