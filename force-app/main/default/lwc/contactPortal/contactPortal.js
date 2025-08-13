import { LightningElement, track } from 'lwc';
import sendVerificationCode from '@salesforce/apex/ContactPortalController.sendVerificationCode';
import verifyAndGetContact from '@salesforce/apex/ContactPortalController.verifyAndGetContact';

export default class ContactPortal extends LightningElement {
  // Reactive properties
  @track email = '';
  @track verificationCode = '';
  @track contactData = {};
  @track errorMessage = '';
  @track successMessage = '';
  @track isLoading = false;
  
  // Step control
  @track showEmailStep = true;
  @track showCodeStep = false;
  @track showContactInfo = false;

  // Input handlers
  handleEmailChange(event) {
      this.email = event.target.value;
      this.clearMessages();
  }

  handleCodeChange(event) {
      this.verificationCode = event.target.value;
      this.clearMessages();
  }

  // Step 1: Send verification code
  async sendVerificationCode() {
      if (!this.validateEmail()) {
          return;
      }

      this.isLoading = true;
      this.clearMessages();

      try {
          const result = await sendVerificationCode({ email: this.email });
          
          if (result.success) {
              this.successMessage = result.message;
              this.showEmailStep = false;
              this.showCodeStep = true;
              
              // Auto-clear success message after 3 seconds
              setTimeout(() => {
                  this.successMessage = '';
              }, 3000);
          }
      } catch (error) {
          this.errorMessage = this.getErrorMessage(error);
      } finally {
          this.isLoading = false;
      }
  }

  // Step 2: Verify code and get contact data
  async verifyCode() {
      if (!this.validateCode()) {
          return;
      }

      this.isLoading = true;
      this.clearMessages();

      try {
          const result = await verifyAndGetContact({ 
              email: this.email, 
              code: this.verificationCode 
          });
          
          if (result.success) {
              this.contactData = result.contact;
              this.showCodeStep = false;
              this.showContactInfo = true;
              this.successMessage = 'Contact information retrieved successfully!';
              
              // Auto-clear success message after 3 seconds
              setTimeout(() => {
                  this.successMessage = '';
              }, 3000);
          }
      } catch (error) {
          this.errorMessage = this.getErrorMessage(error);
      } finally {
          this.isLoading = false;
      }
  }

  // Navigation methods
  goBackToEmail() {
      this.showCodeStep = false;
      this.showEmailStep = true;
      this.verificationCode = '';
      this.clearMessages();
  }

  async resendCode() {
      await this.sendVerificationCode();
  }

  startOver() {
      this.showContactInfo = false;
      this.showEmailStep = true;
      this.email = '';
      this.verificationCode = '';
      this.contactData = {};
      this.clearMessages();
  }

  // Validation methods
  validateEmail() {
      if (!this.email) {
          this.errorMessage = 'Please enter your email address';
          return false;
      }

      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(this.email)) {
          this.errorMessage = 'Please enter a valid email address';
          return false;
      }

      return true;
  }

  validateCode() {
      if (!this.verificationCode) {
          this.errorMessage = 'Please enter the verification code';
          return false;
      }

      if (this.verificationCode.length !== 6) {
          this.errorMessage = 'Verification code must be 6 digits';
          return false;
      }

      if (!/^\d+$/.test(this.verificationCode)) {
          this.errorMessage = 'Verification code must contain only numbers';
          return false;
      }

      return true;
  }

  // Utility methods
  clearMessages() {
      this.errorMessage = '';
      this.successMessage = '';
  }

  clearError() {
      this.errorMessage = '';
  }

  getErrorMessage(error) {
      if (error.body && error.body.message) {
          return error.body.message;
      } else if (error.message) {
          return error.message;
      } else {
          return 'An unexpected error occurred. Please try again.';
      }
  }

  // Getters for computed properties
  get isEmailValid() {
      return this.email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.email);
  }

  get isCodeValid() {
      return this.verificationCode && this.verificationCode.length === 6;
  }
}