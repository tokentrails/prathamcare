package api

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
	"github.com/prathamcare/backend/internal/middleware"
	"github.com/prathamcare/backend/internal/models"
)

type doctorUpsertRequest struct {
	CognitoSub          string   `json:"cognito_sub"`
	FirstName           string   `json:"first_name"`
	MiddleName          string   `json:"middle_name"`
	LastName            string   `json:"last_name"`
	FullName            string   `json:"full_name"`
	Email               string   `json:"email"`
	PhoneNumber         string   `json:"phone_number"`
	Gender              string   `json:"gender"`
	DateOfBirth         string   `json:"date_of_birth"`
	RegistrationNumber  string   `json:"registration_number"`
	Specialization      string   `json:"specialization"`
	Qualifications      string   `json:"qualifications"`
	YearsExperience     int      `json:"years_experience"`
	LanguagesSpoken     []string `json:"languages_spoken"`
	ClinicName          string   `json:"clinic_name"`
	AddressLine1        string   `json:"address_line1"`
	AddressLine2        string   `json:"address_line2"`
	City                string   `json:"city"`
	District            string   `json:"district"`
	State               string   `json:"state"`
	Pincode             string   `json:"pincode"`
	ConsultationMode    struct {
		InPerson    bool `json:"in_person"`
		Telemedicine bool `json:"telemedicine"`
	} `json:"consultation_mode"`
	AvailabilitySummary any   `json:"availability_summary"`
	IsActive            *bool `json:"is_active,omitempty"`
}

func (h *Handler) handleAdminDoctorCreate(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, authResp, err := h.authorizeAdmin(req)
	if err != nil {
		return authResp, nil
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	var in doctorUpsertRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	doctor, code, message := prepareDoctorModel(in)
	if code != "" {
		return h.error(http.StatusBadRequest, code, message)
	}
	doctor.IsActive = true
	doctor.CreatedBy = claims.Subject
	doctor.UpdatedBy = claims.Subject

	writeCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	created, cErr := h.deps.Aurora.CreateDoctor(writeCtx, doctor)
	if cErr != nil {
		if duplicateDoctorField := duplicateDoctorFieldFromErr(cErr.Error()); duplicateDoctorField != "" {
			return h.error(http.StatusConflict, "DUPLICATE_RESOURCE", duplicateDoctorField+" already exists")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to create doctor")
	}
	return h.json(http.StatusCreated, doctorResponse(created))
}

func (h *Handler) handleAdminDoctorList(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	_, authResp, err := h.authorizeAdmin(req)
	if err != nil {
		return authResp, nil
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	params := req.QueryStringParameters
	active, parseErr := parseOptionalBool(params["active"])
	if parseErr != "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", parseErr)
	}
	limit := parseLimit(params, 20, 100)
	offset := parseOffset(params)

	readCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	doctors, lErr := h.deps.Aurora.ListDoctors(readCtx, models.DoctorListFilter{
		Query:          strings.TrimSpace(firstNonEmpty(params["query"], params["q"])),
		Specialization: strings.TrimSpace(params["specialization"]),
		Active:         active,
		Limit:          limit,
		Offset:         offset,
	})
	if lErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to list doctors")
	}

	items := make([]map[string]any, 0, len(doctors))
	for _, doctor := range doctors {
		items = append(items, doctorListItem(doctor))
	}
	return h.json(http.StatusOK, map[string]any{
		"items":  items,
		"count":  len(items),
		"limit":  limit,
		"offset": offset,
	})
}

func (h *Handler) handleAdminDoctorGet(ctx context.Context, req events.APIGatewayV2HTTPRequest, doctorID string) (events.APIGatewayV2HTTPResponse, error) {
	_, authResp, err := h.authorizeAdmin(req)
	if err != nil {
		return authResp, nil
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}
	if !looksLikeUUID(doctorID) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid doctor_id")
	}

	readCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	doctor, gErr := h.deps.Aurora.GetDoctorByID(readCtx, doctorID)
	if gErr != nil {
		if gErr == pgx.ErrNoRows || strings.Contains(strings.ToLower(gErr.Error()), "no rows") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "doctor not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load doctor")
	}
	return h.json(http.StatusOK, doctorResponse(doctor))
}

func (h *Handler) handleAdminDoctorUpdate(ctx context.Context, req events.APIGatewayV2HTTPRequest, doctorID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, authResp, err := h.authorizeAdmin(req)
	if err != nil {
		return authResp, nil
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}
	if !looksLikeUUID(doctorID) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid doctor_id")
	}

	var in doctorUpsertRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	doctor, code, message := prepareDoctorModel(in)
	if code != "" {
		return h.error(http.StatusBadRequest, code, message)
	}
	doctor.DoctorID = doctorID
	doctor.UpdatedBy = claims.Subject
	doctor.IsActive = true
	if in.IsActive != nil {
		doctor.IsActive = *in.IsActive
	}

	writeCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	updated, uErr := h.deps.Aurora.UpdateDoctor(writeCtx, doctor)
	if uErr != nil {
		if uErr == pgx.ErrNoRows || strings.Contains(strings.ToLower(uErr.Error()), "no rows") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "doctor not found")
		}
		if duplicateDoctorField := duplicateDoctorFieldFromErr(uErr.Error()); duplicateDoctorField != "" {
			return h.error(http.StatusConflict, "DUPLICATE_RESOURCE", duplicateDoctorField+" already exists")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to update doctor")
	}
	return h.json(http.StatusOK, doctorResponse(updated))
}

func (h *Handler) handleAdminDoctorStatusUpdate(ctx context.Context, req events.APIGatewayV2HTTPRequest, doctorID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, authResp, err := h.authorizeAdmin(req)
	if err != nil {
		return authResp, nil
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}
	if !looksLikeUUID(doctorID) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid doctor_id")
	}

	var in struct {
		IsActive *bool `json:"is_active"`
	}
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	if in.IsActive == nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "is_active is required")
	}

	writeCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	updated, uErr := h.deps.Aurora.UpdateDoctorStatus(writeCtx, doctorID, *in.IsActive, claims.Subject)
	if uErr != nil {
		if uErr == pgx.ErrNoRows || strings.Contains(strings.ToLower(uErr.Error()), "no rows") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "doctor not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to update doctor status")
	}
	return h.json(http.StatusOK, doctorResponse(updated))
}

func prepareDoctorModel(in doctorUpsertRequest) (models.Doctor, string, string) {
	in.CognitoSub = strings.TrimSpace(in.CognitoSub)
	in.FirstName = strings.TrimSpace(in.FirstName)
	in.MiddleName = strings.TrimSpace(in.MiddleName)
	in.LastName = strings.TrimSpace(in.LastName)
	in.FullName = strings.TrimSpace(in.FullName)
	in.Email = strings.TrimSpace(strings.ToLower(in.Email))
	in.PhoneNumber = strings.TrimSpace(in.PhoneNumber)
	in.Gender = strings.ToLower(strings.TrimSpace(in.Gender))
	in.DateOfBirth = strings.TrimSpace(in.DateOfBirth)
	in.RegistrationNumber = strings.TrimSpace(strings.ToUpper(in.RegistrationNumber))
	in.Specialization = strings.TrimSpace(in.Specialization)
	in.Qualifications = strings.TrimSpace(in.Qualifications)
	in.ClinicName = strings.TrimSpace(in.ClinicName)
	in.AddressLine1 = strings.TrimSpace(in.AddressLine1)
	in.AddressLine2 = strings.TrimSpace(in.AddressLine2)
	in.City = strings.TrimSpace(in.City)
	in.District = strings.TrimSpace(in.District)
	in.State = strings.TrimSpace(in.State)
	in.Pincode = strings.TrimSpace(in.Pincode)

	if in.FirstName == "" {
		return models.Doctor{}, "VALIDATION_ERROR", "first_name is required"
	}
	if in.LastName == "" && in.FullName == "" {
		return models.Doctor{}, "VALIDATION_ERROR", "last_name or full_name is required"
	}
	if in.Email == "" {
		return models.Doctor{}, "VALIDATION_ERROR", "email is required"
	}
	if !regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`).MatchString(in.Email) {
		return models.Doctor{}, "VALIDATION_ERROR", "email must be a valid email address"
	}
	if in.RegistrationNumber == "" {
		return models.Doctor{}, "VALIDATION_ERROR", "registration_number is required"
	}
	if in.Specialization == "" {
		return models.Doctor{}, "VALIDATION_ERROR", "specialization is required"
	}
	normalizedPhone, pErr := normalizeIndianPhone(in.PhoneNumber)
	if pErr != nil {
		return models.Doctor{}, "VALIDATION_ERROR", pErr.Error()
	}
	if in.Pincode != "" && !regexp.MustCompile(`^\d{6}$`).MatchString(in.Pincode) {
		return models.Doctor{}, "VALIDATION_ERROR", "pincode must be 6 digits"
	}
	if in.Gender != "" && !isAllowedGender(in.Gender) {
		return models.Doctor{}, "VALIDATION_ERROR", "gender must be one of male/female/other/unknown"
	}
	dob := ""
	if in.DateOfBirth != "" {
		parsedDOB, dErr := parseDateOnly(in.DateOfBirth)
		if dErr != nil {
			return models.Doctor{}, "VALIDATION_ERROR", "date_of_birth must be YYYY-MM-DD"
		}
		dob = parsedDOB
	}
	if in.YearsExperience < 0 || in.YearsExperience > 80 {
		return models.Doctor{}, "VALIDATION_ERROR", "years_experience must be between 0 and 80"
	}

	fullName := in.FullName
	if fullName == "" {
		fullName = strings.TrimSpace(strings.Join([]string{in.FirstName, in.MiddleName, in.LastName}, " "))
	}
	availabilitySummary := asJSONString(in.AvailabilitySummary)

	return models.Doctor{
		CognitoSub:               in.CognitoSub,
		FirstName:                in.FirstName,
		MiddleName:               in.MiddleName,
		LastName:                 in.LastName,
		FullName:                 fullName,
		Email:                    in.Email,
		PhoneNumber:              normalizedPhone,
		Gender:                   in.Gender,
		DateOfBirth:              dob,
		RegistrationNumber:       in.RegistrationNumber,
		Specialization:           in.Specialization,
		Qualifications:           in.Qualifications,
		YearsExperience:          in.YearsExperience,
		LanguagesSpoken:          sanitizeStringList(in.LanguagesSpoken),
		ClinicName:               in.ClinicName,
		AddressLine1:             in.AddressLine1,
		AddressLine2:             in.AddressLine2,
		City:                     in.City,
		District:                 in.District,
		State:                    in.State,
		Pincode:                  in.Pincode,
		ConsultationInPerson:     in.ConsultationMode.InPerson,
		ConsultationTelemedicine: in.ConsultationMode.Telemedicine,
		AvailabilitySummary:      availabilitySummary,
	}, "", ""
}

func doctorListItem(d models.Doctor) map[string]any {
	return map[string]any{
		"doctor_id":            d.DoctorID,
		"full_name":            d.FullName,
		"first_name":           d.FirstName,
		"last_name":            d.LastName,
		"email":                d.Email,
		"phone_number":         d.PhoneNumber,
		"registration_number":  d.RegistrationNumber,
		"specialization":       d.Specialization,
		"is_active":            d.IsActive,
		"updated_at":           d.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

func doctorResponse(d models.Doctor) map[string]any {
	return map[string]any{
		"doctor_id":            d.DoctorID,
		"cognito_sub":          d.CognitoSub,
		"first_name":           d.FirstName,
		"middle_name":          d.MiddleName,
		"last_name":            d.LastName,
		"full_name":            d.FullName,
		"email":                d.Email,
		"phone_number":         d.PhoneNumber,
		"gender":               d.Gender,
		"date_of_birth":        d.DateOfBirth,
		"registration_number":  d.RegistrationNumber,
		"specialization":       d.Specialization,
		"qualifications":       d.Qualifications,
		"years_experience":     d.YearsExperience,
		"languages_spoken":     d.LanguagesSpoken,
		"clinic_name":          d.ClinicName,
		"address_line1":        d.AddressLine1,
		"address_line2":        d.AddressLine2,
		"city":                 d.City,
		"district":             d.District,
		"state":                d.State,
		"pincode":              d.Pincode,
		"consultation_mode": map[string]bool{
			"in_person":    d.ConsultationInPerson,
			"telemedicine": d.ConsultationTelemedicine,
		},
		"availability_summary": parseJSONAny(d.AvailabilitySummary),
		"is_active":            d.IsActive,
		"created_by":           d.CreatedBy,
		"updated_by":           d.UpdatedBy,
		"created_at":           d.CreatedAt.UTC().Format(time.RFC3339),
		"updated_at":           d.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

func parseJSONAny(raw string) any {
	v := strings.TrimSpace(raw)
	if v == "" {
		return map[string]any{}
	}
	var out any
	if err := json.Unmarshal([]byte(v), &out); err != nil {
		return v
	}
	return out
}

func sanitizeStringList(items []string) []string {
	if len(items) == 0 {
		return []string{}
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		value := strings.TrimSpace(item)
		if value == "" {
			continue
		}
		out = append(out, value)
	}
	return out
}

func parseOptionalBool(raw string) (*bool, string) {
	value := strings.TrimSpace(strings.ToLower(raw))
	if value == "" {
		return nil, ""
	}
	switch value {
	case "true", "1", "yes":
		v := true
		return &v, ""
	case "false", "0", "no":
		v := false
		return &v, ""
	default:
		return nil, "active must be true or false"
	}
}

func parseOffset(params map[string]string) int {
	if params == nil {
		return 0
	}
	if raw, ok := params["offset"]; ok {
		if n, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil && n >= 0 {
			return n
		}
	}
	return 0
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func duplicateDoctorFieldFromErr(errText string) string {
	lower := strings.ToLower(strings.TrimSpace(errText))
	switch {
	case strings.Contains(lower, "uq_doctors_email") || strings.Contains(lower, "(email)"):
		return "email"
	case strings.Contains(lower, "uq_doctors_phone_number") || strings.Contains(lower, "(phone_number)"):
		return "phone_number"
	case strings.Contains(lower, "uq_doctors_registration_number") || strings.Contains(lower, "(registration_number)"):
		return "registration_number"
	case strings.Contains(lower, "uq_doctors_cognito_sub") || strings.Contains(lower, "(cognito_sub)"):
		return "cognito_sub"
	default:
		return ""
	}
}

func (h *Handler) authorizeAdmin(req events.APIGatewayV2HTTPRequest) (middleware.Claims, events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "clinic_admin", "ops_admin")
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "authorization denied") {
			resp, _ := h.error(http.StatusForbidden, "AUTHORIZATION_DENIED", "admin role required")
			return middleware.Claims{}, resp, err
		}
		resp, _ := h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
		return middleware.Claims{}, resp, err
	}
	return claims, events.APIGatewayV2HTTPResponse{}, nil
}
