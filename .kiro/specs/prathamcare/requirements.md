# Requirements Document: PrathamCare

## Introduction

PrathamCare is a unified AI-powered healthcare platform designed for the Indian healthcare ecosystem. The system connects three primary user types—ASHA workers, Patients, and Physicians—through a single Flutter-based application with role-based interfaces. The platform leverages AWS AI services to provide intelligent call-based triage, maintains a shared longitudinal Electronic Medical Record (EMR) using FHIR R4 standards, and generates AI-powered patient summaries to support clinical decision-making.

The MVP focuses on core workflows: ASHA-led patient data capture, AI-driven telephone triage with automatic appointment booking, physician consultation with AI-generated summaries, and patient-contributed remarks that enhance care continuity.

## Glossary

- **System**: The PrathamCare platform (Flutter frontend + Go backend + AWS services)
- **ASHA_Worker**: Accredited Social Health Activist who captures patient data in field settings
- **Patient**: Individual receiving healthcare services through the platform
- **Physician**: Licensed medical doctor providing consultations and prescriptions
- **FHIR_Store**: AWS HealthLake repository storing FHIR R4 resources
- **AI_Triage_Engine**: Amazon Bedrock service that analyzes symptoms and generates assessments
- **Voice_Transcription_Service**: Amazon Transcribe Medical that converts speech to text
- **IVR_System**: Amazon Connect Interactive Voice Response system
- **Symptom_Collector**: Amazon Lex bot that gathers patient symptoms via conversation
- **Authentication_Service**: Amazon Cognito managing user identity and access control
- **Backend_API**: Go monolith Lambda function handling business logic
- **Document_Store**: Amazon S3 bucket storing medical documents and recordings
- **Relational_Database**: Aurora PostgreSQL storing appointments and user data
- **Offline_Queue**: DynamoDB table storing data captured while offline
- **Search_Index**: OpenSearch Serverless index for guideline retrieval
- **ABHA**: Ayushman Bharat Health Account, India's national health ID
- **SOAP_Note**: Subjective, Objective, Assessment, Plan clinical documentation format
- **EMR**: Electronic Medical Record
- **QR_Scanner**: Flutter plugin for scanning ABHA QR codes
- **Role_Based_Access**: Authorization mechanism restricting features by user role

## Requirements

### Requirement 1: User Authentication and Authorization

**User Story:** As a user (ASHA worker, Patient, or Physician), I want to securely log into the system with my phone number, so that I can access role-appropriate features.

#### Acceptance Criteria

1. WHEN a user enters their phone number and requests OTP, THE Authentication_Service SHALL send a one-time password via SMS
2. WHEN a user enters a valid OTP within the expiration window, THE Authentication_Service SHALL issue a JWT token containing user role claims
3. WHEN a user's JWT token is presented to the Backend_API, THE System SHALL validate the token signature and expiration
4. WHERE a user has role ASHA_Worker, THE System SHALL grant access to patient capture and data entry features
5. WHERE a user has role Patient, THE System SHALL grant access to triage calling, appointment viewing, and remark submission features
6. WHERE a user has role Physician, THE System SHALL grant access to appointment management, summary viewing, and prescription features
7. WHEN an invalid or expired token is presented, THE Backend_API SHALL reject the request with an authentication error

### Requirement 2: ASHA Patient Data Capture

**User Story:** As an ASHA worker, I want to capture patient vitals and medical history using voice or text input, so that I can efficiently document patient information during field visits.

#### Acceptance Criteria

1. WHEN an ASHA_Worker selects or creates a patient record, THE System SHALL display a data capture interface with fields for vitals and history
2. WHEN an ASHA_Worker speaks vitals or symptoms, THE Voice_Transcription_Service SHALL convert the audio to text in real-time
3. WHEN transcribed text contains medical entities (vitals, symptoms, measurements), THE System SHALL extract and structure the data into appropriate FHIR Observation resources
4. WHEN an ASHA_Worker captures data while offline, THE System SHALL store the data in Offline_Queue for later synchronization
5. WHEN network connectivity is restored, THE System SHALL automatically sync queued data to FHIR_Store
6. WHEN an ASHA_Worker scans an ABHA QR code, THE QR_Scanner SHALL extract the patient identifier and link it to the patient record
7. WHEN an ASHA_Worker uploads a document (photo, lab report), THE System SHALL store it in Document_Store and create a FHIR DocumentReference

### Requirement 3: Call-Based AI Triage

**User Story:** As a patient, I want to call a phone number and describe my symptoms to an AI system, so that I can receive an initial assessment and be matched with an appropriate physician.

#### Acceptance Criteria

1. WHEN a Patient calls the triage phone number, THE IVR_System SHALL answer and initiate the Symptom_Collector conversation
2. WHEN the Symptom_Collector asks questions, THE Patient SHALL be able to respond in Hindi or English
3. WHEN the Patient describes symptoms in Hindi, THE System SHALL translate the input to English for processing
4. WHEN the Symptom_Collector completes data gathering, THE System SHALL pass the structured symptom data to AI_Triage_Engine
5. WHEN AI_Triage_Engine receives symptom data, THE System SHALL generate a preliminary assessment with urgency level and recommended specialty
6. WHEN the assessment indicates a specialty, THE System SHALL query Relational_Database for available physicians matching that specialty
7. WHEN available physicians are found, THE System SHALL automatically create an appointment record with the best-matched physician
8. WHEN an appointment is created, THE System SHALL send notifications to both Patient and Physician
9. IF no physicians are available, THEN THE System SHALL inform the Patient and offer to add them to a waitlist

### Requirement 4: ABHA Integration

**User Story:** As an ASHA worker or patient, I want to link patient records to their ABHA health ID, so that patient identity is standardized across the healthcare system.

#### Acceptance Criteria

1. WHEN an ASHA_Worker scans an ABHA QR code, THE QR_Scanner SHALL decode the ABHA identifier
2. WHEN an ABHA identifier is decoded, THE System SHALL validate the format against ABHA specifications
3. WHEN a valid ABHA identifier is captured, THE System SHALL store it in the FHIR Patient resource identifier field
4. WHEN creating a new patient record with ABHA, THE System SHALL check if a patient with that ABHA already exists in FHIR_Store
5. IF a patient with the ABHA identifier exists, THEN THE System SHALL link to the existing record instead of creating a duplicate

### Requirement 5: Physician Appointment Management

**User Story:** As a physician, I want to view my scheduled appointments with AI-generated patient summaries, so that I can prepare for consultations efficiently.

#### Acceptance Criteria

1. WHEN a Physician logs in, THE System SHALL display a list of appointments for the current day
2. WHEN a Physician selects an appointment, THE System SHALL retrieve all FHIR resources associated with that patient
3. WHEN FHIR resources are retrieved, THE System SHALL generate a 2-minute summary using AI_Triage_Engine
4. WHEN generating the summary, THE System SHALL include recent vitals, active conditions, medications, allergies, family history, and patient remarks
5. WHEN patient remarks exist, THE System SHALL highlight urgent or clinically relevant remarks in the summary
6. WHEN the summary is displayed, THE System SHALL present it in a structured format with sections for each clinical domain
7. WHEN a Physician marks an appointment as complete, THE System SHALL update the appointment status in Relational_Database

### Requirement 6: Clinical Documentation and SOAP Notes

**User Story:** As a physician, I want to dictate my clinical notes during or after a consultation, so that I can efficiently document the encounter without typing.

#### Acceptance Criteria

1. WHEN a Physician activates voice dictation, THE Voice_Transcription_Service SHALL transcribe the spoken content in real-time
2. WHEN transcription is complete, THE System SHALL structure the content into SOAP note format (Subjective, Objective, Assessment, Plan)
3. WHEN a SOAP note is finalized, THE System SHALL create a FHIR Encounter resource with the note content
4. WHEN clinical entities are mentioned in the note (diagnoses, medications), THE System SHALL extract them and create corresponding FHIR resources (Condition, MedicationRequest)
5. WHEN a Physician issues a prescription, THE System SHALL create FHIR MedicationRequest resources for each medication
6. WHEN a prescription is created, THE System SHALL generate a PDF document with prescription details
7. WHEN the PDF is generated, THE System SHALL store it in Document_Store and make it accessible to the Patient

### Requirement 7: Patient Remarks and Feedback

**User Story:** As a patient, I want to add voice or text remarks about my symptoms or concerns between appointments, so that my physician has the most current information.

#### Acceptance Criteria

1. WHEN a Patient submits a voice remark, THE Voice_Transcription_Service SHALL transcribe it to text
2. WHEN a remark is in Hindi or another regional language, THE System SHALL translate it to English
3. WHEN a remark is transcribed, THE System SHALL analyze it to categorize urgency and clinical relevance
4. WHEN a remark is categorized as urgent, THE System SHALL flag it for physician attention
5. WHEN a remark is stored, THE System SHALL associate it with the patient record in Relational_Database
6. WHEN a Physician views a patient summary, THE System SHALL include recent remarks with urgency indicators
7. WHEN a remark contains medical entities, THE System SHALL extract and highlight them in the physician view

### Requirement 8: Patient Timeline and History

**User Story:** As a patient, I want to view a chronological timeline of my medical encounters, prescriptions, and test results, so that I can track my health journey.

#### Acceptance Criteria

1. WHEN a Patient requests their timeline, THE System SHALL query FHIR_Store for all resources associated with that patient
2. WHEN FHIR resources are retrieved, THE System SHALL sort them chronologically by date
3. WHEN displaying the timeline, THE System SHALL group resources by encounter or date
4. WHEN a Patient selects a timeline entry, THE System SHALL display detailed information for that encounter
5. WHEN prescriptions exist in the timeline, THE System SHALL display medication names, dosages, and duration
6. WHEN lab results exist, THE System SHALL display them with reference ranges and abnormal flags

### Requirement 9: Document Upload and Management

**User Story:** As an ASHA worker or patient, I want to upload medical documents (lab reports, prescriptions, images), so that they are available to physicians during consultations.

#### Acceptance Criteria

1. WHEN a user uploads a document, THE System SHALL validate the file type and size
2. WHEN a valid document is uploaded, THE System SHALL store it in Document_Store with a unique identifier
3. WHEN a document is stored, THE System SHALL create a FHIR DocumentReference resource linking to the S3 object
4. WHEN a document is an image or PDF, THE System SHALL extract text using optical character recognition
5. WHEN text is extracted from a document, THE System SHALL analyze it for medical entities and store structured data
6. WHEN a Physician views a patient summary, THE System SHALL include links to uploaded documents
7. WHEN a user requests a document, THE System SHALL generate a time-limited signed URL for secure access

### Requirement 10: Offline Data Capture and Synchronization

**User Story:** As an ASHA worker, I want to capture patient data even when I don't have internet connectivity, so that I can work in remote areas without disruption.

#### Acceptance Criteria

1. WHEN the System detects no network connectivity, THE System SHALL enable offline mode
2. WHEN in offline mode, THE System SHALL store all captured data locally using device storage
3. WHEN data is captured offline, THE System SHALL queue it in Offline_Queue with a timestamp
4. WHEN network connectivity is restored, THE System SHALL detect the connection and initiate synchronization
5. WHEN synchronizing, THE System SHALL upload queued data to Backend_API in chronological order
6. WHEN synchronization completes successfully, THE System SHALL remove synced data from local storage
7. IF synchronization fails for a specific record, THEN THE System SHALL retry with exponential backoff

### Requirement 11: Physician Matching and Scheduling

**User Story:** As the system, I want to automatically match patients with appropriate physicians based on specialty and availability, so that appointments are efficiently scheduled.

#### Acceptance Criteria

1. WHEN AI_Triage_Engine generates an assessment with a recommended specialty, THE System SHALL query Relational_Database for physicians with that specialty
2. WHEN multiple physicians match the specialty, THE System SHALL filter by current availability in physician_schedule table
3. WHEN available physicians are found, THE System SHALL rank them by earliest available slot
4. WHEN the best match is identified, THE System SHALL create an appointment record with patient, physician, and time slot
5. WHEN an appointment is created, THE System SHALL mark the time slot as booked in physician_schedule
6. WHEN no physicians are available within 48 hours, THE System SHALL add the patient to a waitlist
7. WHEN a physician cancels or adds availability, THE System SHALL check the waitlist and automatically book waiting patients

### Requirement 12: Multi-Language Support

**User Story:** As a patient or ASHA worker, I want to interact with the system in Hindi or my regional language, so that language is not a barrier to healthcare access.

#### Acceptance Criteria

1. WHEN a user selects a language preference, THE System SHALL store it in their user profile
2. WHEN displaying UI text, THE System SHALL render content in the user's preferred language
3. WHEN a user speaks in Hindi during voice input, THE Voice_Transcription_Service SHALL transcribe in Hindi
4. WHEN Hindi text needs to be processed by AI services, THE System SHALL translate it to English
5. WHEN AI-generated content is returned in English, THE System SHALL translate it back to the user's preferred language
6. WHEN translation occurs, THE System SHALL preserve medical terminology accuracy
7. WHEN a Physician views remarks in multiple languages, THE System SHALL display both original and translated versions

### Requirement 13: Data Privacy and Security

**User Story:** As a patient, I want my medical data to be securely stored and accessed only by authorized healthcare providers, so that my privacy is protected.

#### Acceptance Criteria

1. WHEN data is transmitted between client and server, THE System SHALL encrypt it using TLS 1.3
2. WHEN data is stored in FHIR_Store, THE System SHALL encrypt it at rest using KMS-managed keys
3. WHEN a user attempts to access patient data, THE System SHALL verify their role and relationship to the patient
4. WHEN a Physician accesses patient data, THE System SHALL log the access event with timestamp and user identifier
5. WHEN sensitive data (passwords, tokens) is stored, THE System SHALL use Secrets Manager
6. WHEN the System processes payment card data, THE System SHALL comply with PCI DSS standards (future requirement)
7. WHEN a patient requests data deletion, THE System SHALL anonymize or remove their data per GDPR/DPDPA requirements

### Requirement 14: Error Handling and Resilience

**User Story:** As a user, I want the system to handle errors gracefully and retry failed operations, so that temporary issues don't disrupt my workflow.

#### Acceptance Criteria

1. WHEN a Backend_API call fails due to network timeout, THE System SHALL retry the request with exponential backoff
2. WHEN a retry limit is reached, THE System SHALL display a user-friendly error message
3. WHEN an AWS service returns a throttling error, THE System SHALL implement backoff and retry logic
4. WHEN voice transcription fails, THE System SHALL allow the user to re-record or enter text manually
5. WHEN FHIR_Store is temporarily unavailable, THE System SHALL queue write operations for later retry
6. WHEN critical errors occur, THE System SHALL log detailed error information for debugging
7. WHEN the System encounters invalid data, THE System SHALL validate and sanitize input before processing

### Requirement 15: AI Summary Generation

**User Story:** As a physician, I want AI-generated summaries to be accurate, concise, and clinically relevant, so that I can quickly understand a patient's medical history.

#### Acceptance Criteria

1. WHEN generating a summary, THE AI_Triage_Engine SHALL retrieve all FHIR resources for the patient from the past 12 months
2. WHEN FHIR resources are retrieved, THE System SHALL structure them into clinical categories (vitals, conditions, medications, allergies, family history)
3. WHEN patient remarks exist, THE System SHALL include them in the summary with urgency indicators
4. WHEN generating summary text, THE AI_Triage_Engine SHALL produce content that fits within a 2-minute reading time
5. WHEN multiple conditions exist, THE System SHALL prioritize active and chronic conditions over resolved ones
6. WHEN vitals are included, THE System SHALL show trends (improving, worsening, stable) when sufficient data exists
7. WHEN the summary is displayed, THE System SHALL include source citations linking to original FHIR resources

### Requirement 16: Prescription Generation and Management

**User Story:** As a physician, I want to generate electronic prescriptions with proper formatting and drug information, so that patients receive clear medication instructions.

#### Acceptance Criteria

1. WHEN a Physician prescribes a medication, THE System SHALL create a FHIR MedicationRequest resource
2. WHEN creating a MedicationRequest, THE System SHALL include drug name, dosage, frequency, duration, and instructions
3. WHEN a prescription is finalized, THE System SHALL generate a PDF with physician details, patient details, and medication list
4. WHEN generating the PDF, THE System SHALL include a digital signature or verification code
5. WHEN a prescription is created, THE System SHALL check for drug-drug interactions with existing medications
6. IF a potential interaction is detected, THEN THE System SHALL alert the Physician before finalizing
7. WHEN a prescription is issued, THE System SHALL make it available in the Patient's timeline

### Requirement 17: Voice Input Processing

**User Story:** As an ASHA worker or physician, I want voice input to be accurately transcribed and structured, so that I can document information hands-free.

#### Acceptance Criteria

1. WHEN a user activates voice input, THE System SHALL start recording audio
2. WHEN audio is recorded, THE Voice_Transcription_Service SHALL transcribe it with medical vocabulary optimization
3. WHEN transcription is complete, THE System SHALL display the text for user review and correction
4. WHEN medical entities are present in transcribed text, THE System SHALL highlight them for confirmation
5. WHEN a user confirms transcribed content, THE System SHALL extract structured data (vitals, symptoms, diagnoses)
6. WHEN structured data is extracted, THE System SHALL map it to appropriate FHIR resource types
7. WHEN voice input quality is poor, THE System SHALL indicate low confidence and prompt for re-recording

### Requirement 18: Search and Retrieval

**User Story:** As a physician, I want to search for clinical guidelines and patient information quickly, so that I can make informed decisions during consultations.

#### Acceptance Criteria

1. WHEN a Physician searches for a patient by name or ABHA, THE System SHALL query FHIR_Store and return matching patients
2. WHEN a Physician searches for clinical guidelines, THE System SHALL query Search_Index for relevant documents
3. WHEN search results are returned, THE System SHALL rank them by relevance
4. WHEN a Physician selects a search result, THE System SHALL display the full content
5. WHEN searching patient records, THE System SHALL only return patients the Physician is authorized to view
6. WHEN a search query contains medical terms, THE System SHALL expand it with synonyms for better recall
7. WHEN no results are found, THE System SHALL suggest alternative search terms

### Requirement 19: Notification System

**User Story:** As a user, I want to receive timely notifications about appointments, prescriptions, and important updates, so that I stay informed about my healthcare.

#### Acceptance Criteria

1. WHEN an appointment is created, THE System SHALL send a notification to both Patient and Physician
2. WHEN an appointment is within 24 hours, THE System SHALL send a reminder notification
3. WHEN a prescription is issued, THE System SHALL notify the Patient
4. WHEN a patient adds an urgent remark, THE System SHALL notify the assigned Physician
5. WHEN a Physician cancels an appointment, THE System SHALL notify the Patient immediately
6. WHEN notifications are sent, THE System SHALL use the user's preferred channel (SMS, push notification, email)
7. WHEN a notification fails to deliver, THE System SHALL retry and log the failure

### Requirement 20: Configuration and Environment Management

**User Story:** As a system administrator, I want all configuration to be managed through environment variables, so that the system can be deployed across different environments without code changes.

#### Acceptance Criteria

1. WHEN the Backend_API starts, THE System SHALL load all configuration from environment variables
2. WHEN a required environment variable is missing, THE System SHALL fail to start with a clear error message
3. WHEN connecting to AWS services, THE System SHALL use credentials from environment or IAM roles
4. WHEN database connection parameters change, THE System SHALL read updated values from environment variables
5. WHEN feature flags are needed, THE System SHALL read them from environment configuration
6. WHEN logging levels are configured, THE System SHALL respect the LOG_LEVEL environment variable
7. WHEN deploying to different environments (dev, staging, prod), THE System SHALL use environment-specific configuration without code changes

