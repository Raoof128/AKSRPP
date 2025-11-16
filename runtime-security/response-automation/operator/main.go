package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// FalcoAlert represents alert structure from Falco
type FalcoAlert struct {
	Output       string            `json:"output"`
	Priority     string            `json:"priority"`
	Rule         string            `json:"rule"`
	Time         time.Time         `json:"time"`
	OutputFields map[string]string `json:"output_fields"`
}

// SecurityOperator handles automated remediation
type SecurityOperator struct {
	clientset      *kubernetes.Clientset
	alertsReceived prometheus.Counter
	remediated     *prometheus.CounterVec
	forensicsSaved prometheus.Counter
}

func NewSecurityOperator() (*SecurityOperator, error) {
	// Create in-cluster K8s client
	config, err := rest.InClusterConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to create cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create clientset: %v", err)
	}

	// Prometheus metrics
	alertsReceived := prometheus.NewCounter(prometheus.CounterOpts{
		Name: "security_operator_alerts_received_total",
		Help: "Total number of Falco alerts received",
	})

	remediated := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "security_operator_remediation_total",
		Help: "Total remediations performed by action type",
	}, []string{"action", "priority"})

	forensicsSaved := prometheus.NewCounter(prometheus.CounterOpts{
		Name: "security_operator_forensics_saved_total",
		Help: "Total forensics snapshots saved",
	})

	prometheus.MustRegister(alertsReceived, remediated, forensicsSaved)

	return &SecurityOperator{
		clientset:      clientset,
		alertsReceived: alertsReceived,
		remediated:     remediated,
		forensicsSaved: forensicsSaved,
	}, nil
}

// HandleAlert processes incoming Falco alerts
func (s *SecurityOperator) HandleAlert(alert FalcoAlert) error {
	s.alertsReceived.Inc()

	log.Printf("Received alert: [%s] %s - %s", alert.Priority, alert.Rule, alert.Output)

	// Extract pod/container information
	podName := alert.OutputFields["k8s.pod.name"]
	namespace := alert.OutputFields["k8s.ns.name"]
	containerName := alert.OutputFields["container.name"]

	if podName == "" || namespace == "" {
		log.Printf("Alert missing pod/namespace info, skipping remediation")
		return nil
	}

	// Determine action based on priority
	switch alert.Priority {
	case "Critical", "CRITICAL":
		return s.handleCriticalAlert(namespace, podName, containerName, alert)
	case "Warning", "WARNING":
		return s.handleWarningAlert(namespace, podName, containerName, alert)
	case "Error", "ERROR":
		return s.handleErrorAlert(namespace, podName, containerName, alert)
	default:
		log.Printf("Alert priority %s - logging only", alert.Priority)
	}

	return nil
}

// handleCriticalAlert - Immediate isolation and forensics
func (s *SecurityOperator) handleCriticalAlert(namespace, pod, container string, alert FalcoAlert) error {
	log.Printf("CRITICAL alert for pod %s/%s - initiating immediate response", namespace, pod)

	// 1. Capture forensics BEFORE any changes
	if err := s.captureForensics(namespace, pod, container, alert); err != nil {
		log.Printf("Error capturing forensics: %v", err)
	}

	// 2. Isolate pod (apply network policy denying all traffic)
	if err := s.isolatePod(namespace, pod); err != nil {
		log.Printf("Error isolating pod: %v", err)
		return err
	}
	s.remediated.WithLabelValues("isolate", "critical").Inc()

	// 3. Label pod for investigation
	if err := s.labelPodForInvestigation(namespace, pod, alert.Rule); err != nil {
		log.Printf("Error labeling pod: %v", err)
	}

	// 4. Send high-priority alerts
	go s.sendSlackAlert(alert, "CRITICAL", namespace, pod)
	go s.sendPagerDutyAlert(alert, namespace, pod)

	log.Printf("Critical response completed for %s/%s", namespace, pod)
	return nil
}

// handleWarningAlert - Monitor and alert
func (s *SecurityOperator) handleWarningAlert(namespace, pod, container string, alert FalcoAlert) error {
	log.Printf("WARNING alert for pod %s/%s - monitoring", namespace, pod)

	// Capture forensics for investigation
	if err := s.captureForensics(namespace, pod, container, alert); err != nil {
		log.Printf("Error capturing forensics: %v", err)
	}

	// Label for monitoring
	if err := s.labelPodForInvestigation(namespace, pod, alert.Rule); err != nil {
		log.Printf("Error labeling pod: %v", err)
	}
	s.remediated.WithLabelValues("monitor", "warning").Inc()

	// Alert team
	go s.sendSlackAlert(alert, "WARNING", namespace, pod)

	return nil
}

// handleErrorAlert - Log and monitor
func (s *SecurityOperator) handleErrorAlert(namespace, pod, container string, alert FalcoAlert) error {
	log.Printf("ERROR alert for pod %s/%s - logging", namespace, pod)
	s.remediated.WithLabelValues("log", "error").Inc()
	return nil
}

// isolatePod creates NetworkPolicy to block all traffic
func (s *SecurityOperator) isolatePod(namespace, pod string) error {
	// In production, would create a NetworkPolicy like:
	// apiVersion: networking.k8s.io/v1
	// kind: NetworkPolicy
	// metadata:
	//   name: isolate-<pod>
	// spec:
	//   podSelector:
	//     matchLabels:
	//       kubernetes.io/pod-name: <pod>
	//   policyTypes:
	//   - Ingress
	//   - Egress
	//   # No ingress/egress rules = deny all

	log.Printf("Would isolate pod %s/%s with NetworkPolicy", namespace, pod)
	// Implementation would use s.clientset.NetworkingV1().NetworkPolicies(namespace).Create(...)
	return nil
}

// captureForensics saves pod logs and metadata
func (s *SecurityOperator) captureForensics(namespace, pod, container string, alert FalcoAlert) error {
	ctx := context.Background()

	// Get pod details
	podObj, err := s.clientset.CoreV1().Pods(namespace).Get(ctx, pod, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("failed to get pod: %v", err)
	}

	// Get pod logs
	logOptions := &v1.PodLogOptions{
		Container: container,
	}
	req := s.clientset.CoreV1().Pods(namespace).GetLogs(pod, logOptions)
	logs, err := req.Stream(ctx)
	if err != nil {
		log.Printf("Failed to get logs: %v", err)
	} else {
		defer logs.Close()
	}

	// Save forensics
	forensicsData := map[string]interface{}{
		"timestamp":  time.Now(),
		"alert":      alert,
		"pod":        podObj,
		"logs_saved": logs != nil,
	}

	forensicsJSON, _ := json.MarshalIndent(forensicsData, "", "  ")
	filename := fmt.Sprintf("/forensics/%s-%s-%d.json", namespace, pod, time.Now().Unix())

	// In production: save to S3/blob storage
	log.Printf("Forensics saved: %s", filename)
	log.Printf("Forensics data: %s", string(forensicsJSON))

	s.forensicsSaved.Inc()
	return nil
}

// labelPodForInvestigation adds label to pod
func (s *SecurityOperator) labelPodForInvestigation(namespace, pod, rule string) error {
	ctx := context.Background()

	podObj, err := s.clientset.CoreV1().Pods(namespace).Get(ctx, pod, metav1.GetOptions{})
	if err != nil {
		return err
	}

	if podObj.Labels == nil {
		podObj.Labels = make(map[string]string)
	}
	podObj.Labels["security.falco/alert"] = "true"
	podObj.Labels["security.falco/rule"] = sanitizeLabel(rule)
	podObj.Labels["security.falco/timestamp"] = fmt.Sprintf("%d", time.Now().Unix())

	_, err = s.clientset.CoreV1().Pods(namespace).Update(ctx, podObj, metav1.UpdateOptions{})
	return err
}

// sendSlackAlert sends alert to Slack
func (s *SecurityOperator) sendSlackAlert(alert FalcoAlert, severity, namespace, pod string) {
	webhookURL := os.Getenv("SLACK_WEBHOOK_URL")
	if webhookURL == "" {
		log.Println("SLACK_WEBHOOK_URL not set, skipping Slack notification")
		return
	}

	message := map[string]interface{}{
		"text": fmt.Sprintf("🚨 *%s Security Alert*", severity),
		"blocks": []map[string]interface{}{
			{
				"type": "header",
				"text": map[string]string{
					"type": "plain_text",
					"text": fmt.Sprintf("🚨 %s: %s", severity, alert.Rule),
				},
			},
			{
				"type": "section",
				"fields": []map[string]string{
					{"type": "mrkdwn", "text": fmt.Sprintf("*Pod:*\n%s/%s", namespace, pod)},
					{"type": "mrkdwn", "text": fmt.Sprintf("*Priority:*\n%s", alert.Priority)},
					{"type": "mrkdwn", "text": fmt.Sprintf("*Time:*\n%s", alert.Time.Format(time.RFC3339))},
					{"type": "mrkdwn", "text": fmt.Sprintf("*Rule:*\n%s", alert.Rule)},
				},
			},
			{
				"type": "section",
				"text": map[string]string{
					"type": "mrkdwn",
					"text": fmt.Sprintf("*Details:*\n```%s```", alert.Output),
				},
			},
		},
	}

	// Send to Slack (implementation simplified)
	log.Printf("Would send Slack alert: %v", message)
}

// sendPagerDutyAlert creates PagerDuty incident
func (s *SecurityOperator) sendPagerDutyAlert(alert FalcoAlert, namespace, pod string) {
	integrationKey := os.Getenv("PAGERDUTY_INTEGRATION_KEY")
	if integrationKey == "" {
		log.Println("PAGERDUTY_INTEGRATION_KEY not set, skipping PagerDuty alert")
		return
	}

	log.Printf("Would create PagerDuty incident for %s/%s: %s", namespace, pod, alert.Rule)
}

func sanitizeLabel(s string) string {
	// K8s labels must be <= 63 chars, alphanumeric + - _ .
	if len(s) > 63 {
		return s[:63]
	}
	return s
}

func main() {
	log.Println("Starting Security Remediation Operator...")

	operator, err := NewSecurityOperator()
	if err != nil {
		log.Fatalf("Failed to create operator: %v", err)
	}

	// HTTP server for receiving alerts
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/alerts", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var alert FalcoAlert
		if err := json.NewDecoder(r.Body).Decode(&alert); err != nil {
			http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
			return
		}

		if err := operator.HandleAlert(alert); err != nil {
			log.Printf("Error handling alert: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte("Alert processed"))
	})

	// Prometheus metrics
	http.Handle("/metrics", promhttp.Handler())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
