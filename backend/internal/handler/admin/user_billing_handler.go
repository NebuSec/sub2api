package admin

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/handler/dto"
	infraerrors "github.com/Wei-Shaw/sub2api/internal/pkg/errors"
	"github.com/Wei-Shaw/sub2api/internal/pkg/response"
	"github.com/Wei-Shaw/sub2api/internal/pkg/timezone"
	"github.com/Wei-Shaw/sub2api/internal/pkg/usagestats"
	"github.com/Wei-Shaw/sub2api/internal/service"

	"github.com/gin-gonic/gin"
)

// UserBillingHandler handles admin user billing adjunct routes.
type UserBillingHandler struct {
	adminService        service.AdminService
	apiKeyService       *service.APIKeyService
	usageService        *service.UsageService
	billingCacheService *service.BillingCacheService
	subscriptionService *service.SubscriptionService
}

// NewUserBillingHandler creates a user billing handler without expanding UserHandler.
func NewUserBillingHandler(
	adminService service.AdminService,
	apiKeyService *service.APIKeyService,
	usageService *service.UsageService,
	billingCacheService *service.BillingCacheService,
	subscriptionService *service.SubscriptionService,
) *UserBillingHandler {
	return &UserBillingHandler{
		adminService:        adminService,
		apiKeyService:       apiKeyService,
		usageService:        usageService,
		billingCacheService: billingCacheService,
		subscriptionService: subscriptionService,
	}
}

// CreateUserAPIKeyRequest represents an admin request to create an API key for a user.
type CreateUserAPIKeyRequest struct {
	Name          string   `json:"name" binding:"required"`
	GroupID       *int64   `json:"group_id"`
	CustomKey     *string  `json:"custom_key"`
	IPWhitelist   []string `json:"ip_whitelist"`
	IPBlacklist   []string `json:"ip_blacklist"`
	Quota         *float64 `json:"quota"`
	ExpiresInDays *int     `json:"expires_in_days"`
	RateLimit5h   *float64 `json:"rate_limit_5h"`
	RateLimit1d   *float64 `json:"rate_limit_1d"`
	RateLimit7d   *float64 `json:"rate_limit_7d"`
}

type BillingEligibilityRequest struct {
	APIKeyID *int64 `json:"api_key_id"`
	Platform string `json:"platform"`
}

// CreateUserAPIKey handles creating an API key for a specific user.
// POST /api/v1/admin/users/:id/keys
func (h *UserBillingHandler) CreateUserAPIKey(c *gin.Context) {
	userID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "Invalid user ID")
		return
	}

	var req CreateUserAPIKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Invalid request: "+err.Error())
		return
	}

	svcReq := service.CreateAPIKeyRequest{
		Name:          req.Name,
		GroupID:       req.GroupID,
		CustomKey:     req.CustomKey,
		IPWhitelist:   req.IPWhitelist,
		IPBlacklist:   req.IPBlacklist,
		ExpiresInDays: req.ExpiresInDays,
	}
	if req.Quota != nil {
		svcReq.Quota = *req.Quota
	}
	if req.RateLimit5h != nil {
		svcReq.RateLimit5h = *req.RateLimit5h
	}
	if req.RateLimit1d != nil {
		svcReq.RateLimit1d = *req.RateLimit1d
	}
	if req.RateLimit7d != nil {
		svcReq.RateLimit7d = *req.RateLimit7d
	}

	key, err := h.apiKeyService.Create(c.Request.Context(), userID, svcReq)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	response.Success(c, dto.APIKeyFromService(key))
}

// GetBillingSummary returns a single billing snapshot for a user.
// GET /api/v1/admin/users/:id/billing-summary
func (h *UserBillingHandler) GetBillingSummary(c *gin.Context) {
	userID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "Invalid user ID")
		return
	}
	if h.usageService == nil {
		response.ErrorFrom(c, infraerrors.ServiceUnavailable("USAGE_SERVICE_UNAVAILABLE", "usage service unavailable"))
		return
	}

	user, err := h.adminService.GetUser(c.Request.Context(), userID)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	keys, _, err := h.adminService.GetUserAPIKeys(c.Request.Context(), userID, 1, 1000, "id", "asc")
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	startTime, endTime := parseBillingSummaryTimeRange(c)
	granularity := strings.TrimSpace(c.DefaultQuery("granularity", "day"))
	if granularity == "" {
		granularity = "day"
	}

	periodStats, err := h.usageService.GetStatsWithFilters(c.Request.Context(), usagestats.UsageLogFilters{
		UserID:    userID,
		StartTime: &startTime,
		EndTime:   &endTime,
	})
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	todayStart := timezoneStartOfToday(c)
	todayStats, err := h.usageService.GetStatsWithFilters(c.Request.Context(), usagestats.UsageLogFilters{
		UserID:    userID,
		StartTime: &todayStart,
		EndTime:   &endTime,
	})
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	trend, err := h.usageService.GetUserUsageTrendByUserID(c.Request.Context(), userID, startTime, endTime, granularity)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	keyDTOs := make([]dto.APIKey, 0, len(keys))
	for i := range keys {
		keyDTOs = append(keyDTOs, *dto.APIKeyFromService(&keys[i]))
	}

	response.Success(c, gin.H{
		"user":         dto.UserFromServiceAdmin(user),
		"api_keys":     keyDTOs,
		"period_stats": periodStats,
		"today_stats":  todayStats,
		"trend":        trend,
		"range": gin.H{
			"start_date":  startTime.Format("2006-01-02"),
			"end_date":    endTime.AddDate(0, 0, -1).Format("2006-01-02"),
			"granularity": granularity,
		},
	})
}

// CheckBillingEligibility checks whether a user can start a request/scan without consuming RPM counters.
// POST /api/v1/admin/users/:id/billing-eligibility
func (h *UserBillingHandler) CheckBillingEligibility(c *gin.Context) {
	userID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "Invalid user ID")
		return
	}
	if h.billingCacheService == nil {
		response.ErrorFrom(c, infraerrors.ServiceUnavailable("BILLING_SERVICE_UNAVAILABLE", "billing service unavailable"))
		return
	}

	var req BillingEligibilityRequest
	if c.Request.Body != nil && c.Request.ContentLength != 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			response.BadRequest(c, "Invalid request: "+err.Error())
			return
		}
	}

	apiKey, err := h.resolveUserBillingAPIKey(c.Request.Context(), userID, req.APIKeyID)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}
	subscription, err := h.resolveBillingSubscription(c.Request.Context(), apiKey)
	if err != nil {
		h.writeBillingEligibility(c, false, apiKey, strings.TrimSpace(req.Platform), err)
		return
	}

	platform := strings.TrimSpace(req.Platform)
	if platform == "" {
		platform = service.QuotaPlatform(c.Request.Context(), apiKey)
	}

	err = h.billingCacheService.CheckBillingEligibilitySnapshot(c.Request.Context(), apiKey.User, apiKey, apiKey.Group, subscription, platform)
	h.writeBillingEligibility(c, err == nil, apiKey, platform, err)
}

func (h *UserBillingHandler) resolveUserBillingAPIKey(ctx context.Context, userID int64, apiKeyID *int64) (*service.APIKey, error) {
	if h.apiKeyService == nil {
		return nil, infraerrors.ServiceUnavailable("API_KEY_SERVICE_UNAVAILABLE", "api key service unavailable")
	}
	if apiKeyID != nil {
		key, err := h.apiKeyService.GetByID(ctx, *apiKeyID)
		if err != nil {
			return nil, err
		}
		if key.UserID != userID {
			return nil, infraerrors.Forbidden("API_KEY_USER_MISMATCH", "API key does not belong to user")
		}
		return key, nil
	}

	keys, _, err := h.adminService.GetUserAPIKeys(ctx, userID, 1, 1000, "id", "asc")
	if err != nil {
		return nil, err
	}
	for i := range keys {
		if keys[i].Status == service.StatusAPIKeyActive {
			return h.apiKeyService.GetByID(ctx, keys[i].ID)
		}
	}
	return nil, infraerrors.NotFound("API_KEY_NOT_FOUND", "user has no active API key")
}

func (h *UserBillingHandler) resolveBillingSubscription(ctx context.Context, apiKey *service.APIKey) (*service.UserSubscription, error) {
	if apiKey == nil || apiKey.Group == nil || !apiKey.Group.IsSubscriptionType() {
		return nil, nil
	}
	if h.subscriptionService == nil {
		return nil, infraerrors.Forbidden("SUBSCRIPTION_NOT_FOUND", "No active subscription found for this group")
	}
	subscription, err := h.subscriptionService.GetActiveSubscription(ctx, apiKey.UserID, apiKey.Group.ID)
	if err != nil {
		return nil, infraerrors.Forbidden("SUBSCRIPTION_NOT_FOUND", "No active subscription found for this group").WithCause(err)
	}
	return subscription, nil
}

func (h *UserBillingHandler) writeBillingEligibility(c *gin.Context, allowed bool, apiKey *service.APIKey, platform string, err error) {
	payload := gin.H{
		"allowed":  allowed,
		"platform": platform,
	}
	if apiKey != nil {
		payload["user_id"] = apiKey.UserID
		payload["api_key_id"] = apiKey.ID
		if apiKey.GroupID != nil && apiKey.Group != nil && apiKey.Group.IsSubscriptionType() {
			payload["billing_mode"] = "subscription"
		} else {
			payload["billing_mode"] = "balance"
		}
		if apiKey.User != nil {
			payload["balance"] = apiKey.User.Balance
		}
	}
	if err != nil {
		payload["reason"] = infraerrors.Reason(err)
		payload["message"] = infraerrors.Message(err)
		if appErr := infraerrors.FromError(err); appErr != nil && appErr.Metadata != nil {
			payload["metadata"] = appErr.Metadata
		}
	}
	response.Success(c, payload)
}

func timezoneStartOfToday(c *gin.Context) time.Time {
	userTZ := c.Query("timezone")
	return timezone.StartOfDayInUserLocation(timezone.NowInUserLocation(userTZ), userTZ)
}

func parseBillingSummaryTimeRange(c *gin.Context) (time.Time, time.Time) {
	userTZ := c.Query("timezone")
	now := timezone.NowInUserLocation(userTZ)
	startDate := strings.TrimSpace(c.Query("start_date"))
	endDate := strings.TrimSpace(c.Query("end_date"))

	startTime := timezone.StartOfDayInUserLocation(now.AddDate(0, 0, -30), userTZ)
	if startDate != "" {
		if t, err := timezone.ParseInUserLocation("2006-01-02", startDate, userTZ); err == nil {
			startTime = t
		}
	}

	endTime := timezone.StartOfDayInUserLocation(now.AddDate(0, 0, 1), userTZ)
	if endDate != "" {
		if t, err := timezone.ParseInUserLocation("2006-01-02", endDate, userTZ); err == nil {
			endTime = t.AddDate(0, 0, 1)
		}
	}
	return startTime, endTime
}
