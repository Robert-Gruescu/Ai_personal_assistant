"""
Email Service
Handles sending and reading emails
"""
import smtplib
import imaplib
import email
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import decode_header
from typing import Dict, Any, Optional, List
from datetime import datetime
from app.config import SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, IMAP_HOST, IMAP_PORT


class EmailService:
    """Handles email sending for the agent"""
    
    def __init__(self):
        self.host = SMTP_HOST
        self.port = SMTP_PORT
        self.user = SMTP_USER
        self.password = SMTP_PASSWORD
        self.is_configured = bool(self.user and self.password)
    
    def send_email(
        self,
        to_email: str,
        subject: str,
        body: str,
        is_html: bool = False
    ) -> Dict[str, Any]:
        """
        Send an email
        
        Args:
            to_email: Recipient email address
            subject: Email subject
            body: Email body content
            is_html: Whether body is HTML
            
        Returns:
            Dict with success status and any errors
        """
        if not self.is_configured:
            return {
                "success": False,
                "error": "Email service not configured. Please set SMTP credentials in .env"
            }
        
        try:
            # Create message
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = self.user
            msg["To"] = to_email
            
            # Add body
            content_type = "html" if is_html else "plain"
            msg.attach(MIMEText(body, content_type))
            
            # Send email
            with smtplib.SMTP(self.host, self.port) as server:
                server.starttls()
                server.login(self.user, self.password)
                server.sendmail(self.user, to_email, msg.as_string())
            
            return {
                "success": True,
                "message": f"Email sent to {to_email}",
                "sent_at": datetime.utcnow().isoformat()
            }
            
        except smtplib.SMTPAuthenticationError:
            return {
                "success": False,
                "error": "Email authentication failed. Check SMTP credentials."
            }
        except smtplib.SMTPException as e:
            return {
                "success": False,
                "error": f"SMTP error: {str(e)}"
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to send email: {str(e)}"
            }
    
    def validate_email(self, email: str) -> bool:
        """Basic email validation"""
        import re
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return bool(re.match(pattern, email))
    
    def _decode_header_value(self, value: str) -> str:
        """Decode email header value"""
        if value is None:
            return ""
        decoded_parts = decode_header(value)
        result = ""
        for part, encoding in decoded_parts:
            if isinstance(part, bytes):
                result += part.decode(encoding or 'utf-8', errors='ignore')
            else:
                result += part
        return result
    
    def _get_email_body(self, msg) -> str:
        """Extract email body from message"""
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get("Content-Disposition"))
                
                if content_type == "text/plain" and "attachment" not in content_disposition:
                    try:
                        payload = part.get_payload(decode=True)
                        if payload:
                            charset = part.get_content_charset() or 'utf-8'
                            body = payload.decode(charset, errors='ignore')
                            break
                    except:
                        pass
                elif content_type == "text/html" and "attachment" not in content_disposition and not body:
                    try:
                        payload = part.get_payload(decode=True)
                        if payload:
                            charset = part.get_content_charset() or 'utf-8'
                            # Strip HTML tags for plain text
                            import re
                            html_body = payload.decode(charset, errors='ignore')
                            body = re.sub('<[^<]+?>', '', html_body)
                            body = re.sub(r'\s+', ' ', body).strip()
                    except:
                        pass
        else:
            try:
                payload = msg.get_payload(decode=True)
                if payload:
                    charset = msg.get_content_charset() or 'utf-8'
                    body = payload.decode(charset, errors='ignore')
            except:
                body = str(msg.get_payload())
        
        return body.strip()
    
    def get_recent_emails(self, count: int = 10, folder: str = "INBOX") -> Dict[str, Any]:
        """
        Get recent emails from inbox
        
        Args:
            count: Number of emails to fetch
            folder: Email folder to read from
            
        Returns:
            Dict with emails list or error
        """
        if not self.is_configured:
            return {
                "success": False,
                "error": "Email service not configured. Please set SMTP credentials in .env"
            }
        
        try:
            # Connect to IMAP server
            mail = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
            mail.login(self.user, self.password)
            mail.select(folder)
            
            # Search for all emails
            status, messages = mail.search(None, "ALL")
            if status != "OK":
                return {"success": False, "error": "Failed to search emails"}
            
            email_ids = messages[0].split()
            
            # Get the last 'count' emails
            recent_ids = email_ids[-count:] if len(email_ids) >= count else email_ids
            recent_ids = list(reversed(recent_ids))  # Most recent first
            
            emails = []
            for email_id in recent_ids:
                status, msg_data = mail.fetch(email_id, "(RFC822)")
                if status != "OK":
                    continue
                
                for response_part in msg_data:
                    if isinstance(response_part, tuple):
                        msg = email.message_from_bytes(response_part[1])
                        
                        # Extract email details
                        subject = self._decode_header_value(msg["Subject"])
                        from_addr = self._decode_header_value(msg["From"])
                        date = msg["Date"]
                        body = self._get_email_body(msg)
                        
                        # Truncate body if too long
                        if len(body) > 2000:
                            body = body[:2000] + "..."
                        
                        emails.append({
                            "id": email_id.decode(),
                            "subject": subject,
                            "from": from_addr,
                            "date": date,
                            "body": body,
                            "preview": body[:200] + "..." if len(body) > 200 else body
                        })
            
            mail.close()
            mail.logout()
            
            return {
                "success": True,
                "count": len(emails),
                "emails": emails
            }
            
        except imaplib.IMAP4.error as e:
            return {
                "success": False,
                "error": f"IMAP error: {str(e)}"
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to read emails: {str(e)}"
            }
    
    def get_email_by_index(self, index: int = 0) -> Dict[str, Any]:
        """
        Get a specific email by index (0 = most recent)
        
        Args:
            index: Email index (0 = most recent)
            
        Returns:
            Dict with email details or error
        """
        result = self.get_recent_emails(count=index + 1)
        if not result["success"]:
            return result
        
        emails = result.get("emails", [])
        if index >= len(emails):
            return {
                "success": False,
                "error": f"Email at index {index} not found"
            }
        
        return {
            "success": True,
            "email": emails[index]
        }
    
    def search_emails(self, query: str, count: int = 5) -> Dict[str, Any]:
        """
        Search emails by subject or sender
        
        Args:
            query: Search query
            count: Max results to return
            
        Returns:
            Dict with matching emails
        """
        result = self.get_recent_emails(count=50)  # Search in last 50 emails
        if not result["success"]:
            return result
        
        query_lower = query.lower()
        matching = []
        
        for email_item in result.get("emails", []):
            subject = email_item.get("subject", "").lower()
            from_addr = email_item.get("from", "").lower()
            body = email_item.get("body", "").lower()
            
            if query_lower in subject or query_lower in from_addr or query_lower in body:
                matching.append(email_item)
                if len(matching) >= count:
                    break
        
        return {
            "success": True,
            "query": query,
            "count": len(matching),
            "emails": matching
        }


# Singleton instance
email_service = EmailService()
