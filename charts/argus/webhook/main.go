package main

import (
	"context"
	"crypto/tls"
	//"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	//"strings"

	admissionv1 "k8s.io/api/admission/v1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
)

var (
	scheme = runtime.NewScheme()
	codecs = serializer.NewCodecFactory(scheme)
)

type WebhookServer struct {
	server    *http.Server
	k8sClient kubernetes.Interface
}

type patchOperation struct {
	Op    string      `json:"op"`
	Path  string      `json:"path"`
	Value interface{} `json:"value,omitempty"`
}

func main() {
	// Initialize Kubernetes client
	config, err := rest.InClusterConfig()
	if err != nil {
		klog.Fatalf("Failed to create in-cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		klog.Fatalf("Failed to create Kubernetes client: %v", err)
	}

	// Load TLS certificates
	certPath := "/etc/webhook/certs/tls.crt"
	keyPath := "/etc/webhook/certs/tls.key"
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		klog.Fatalf("Failed to load key pair: %v", err)
	}

	server := &WebhookServer{
		k8sClient: clientset,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/mutate", server.mutate)
	mux.HandleFunc("/health", server.health)

	server.server = &http.Server{
		Addr:      ":8443",
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{cert}},
		Handler:   mux,
	}

	klog.Info("Starting webhook server...")
	if err := server.server.ListenAndServeTLS("", ""); err != nil {
		klog.Fatalf("Failed to start webhook server: %v", err)
	}
}

func (ws *WebhookServer) health(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func (ws *WebhookServer) mutate(w http.ResponseWriter, r *http.Request) {
	klog.Info("🎯 === WEBHOOK MUTATE REQUEST RECEIVED ===")
	klog.Infof("Request from: %s %s", r.Method, r.URL.Path)
	var body []byte
	if r.Body != nil {
		if data, err := io.ReadAll(r.Body); err == nil {
			body = data
		}
	}

	// Parse the admission request
	var admissionResponse *admissionv1.AdmissionResponse
	ar := admissionv1.AdmissionReview{}
	if err := json.Unmarshal(body, &ar); err != nil {
		klog.Errorf("Could not unmarshal request: %v", err)
		admissionResponse = &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	} else {
		klog.Info("🎯 Calling mutateDeployment...")
		admissionResponse = ws.mutateDeployment(&ar)
		klog.Info("🎯 mutateDeployment completed")
	}

	admissionReview := admissionv1.AdmissionReview{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "admission.k8s.io/v1",
			Kind:       "AdmissionReview",
		},
	}
	if admissionResponse != nil {
		admissionReview.Response = admissionResponse
		if ar.Request != nil {
			admissionReview.Response.UID = ar.Request.UID
		}
		klog.Infof("📋 Admission response: Allowed=%t, PatchType=%v, PatchSize=%d", 
			admissionResponse.Allowed, 
			admissionResponse.PatchType, 
			len(admissionResponse.Patch))
	} else {
		klog.Error("❌ admissionResponse is nil!")
	}

	respBytes, _ := json.Marshal(admissionReview)
	w.Header().Set("Content-Type", "application/json")
	w.Write(respBytes)
	
	klog.Info("🎯 === WEBHOOK MUTATE REQUEST COMPLETED ===")
}

func (ws *WebhookServer) mutateDeployment(ar *admissionv1.AdmissionReview) *admissionv1.AdmissionResponse {
	req := ar.Request
	var deployment appsv1.Deployment
	if err := json.Unmarshal(req.Object.Raw, &deployment); err != nil {
		klog.Errorf("Could not unmarshal raw object: %v", err)
		return &admissionv1.AdmissionResponse{
			UID:     req.UID,
			Allowed: false,
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	// Check if this is an argus or collectorset deployment
	deploymentType := ws.getDeploymentType(&deployment)
	if deploymentType == "unknown" {
		klog.Infof("Not an argus or collectorset deployment, allowing without changes")
		return &admissionv1.AdmissionResponse{
			UID:     req.UID,
			Allowed: true,
		}
	}
	
	klog.Infof("Detected %s deployment", deploymentType)

	klog.Infof("Mutating %s deployment: %s/%s", deploymentType, deployment.Namespace, deployment.Name)
	klog.Infof("Deployment has %d containers", len(deployment.Spec.Template.Spec.Containers))
	
	// Log container details
	for i, container := range deployment.Spec.Template.Spec.Containers {
		envCount := 0
		if container.Env != nil {
			envCount = len(container.Env)
		}
		klog.Infof("Container %d: name=%s, existing_env_vars=%d", i, container.Name, envCount)
	}

	var patches []patchOperation

	// Get environment variables based on deployment type
	var envVars []corev1.EnvVar
	var err error
	
	switch deploymentType {
	case "argus":
		envVars, err = ws.getArgusEnvironmentVariables(req.Namespace)
	case "collectorset":
		envVars, err = ws.getCollectorsetEnvironmentVariables(req.Namespace, req.Name)
	}
	
	if err != nil {
		klog.Errorf("Failed to get environment variables: %v", err)
		return &admissionv1.AdmissionResponse{
			UID:     req.UID,
			Allowed: false,
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}
	
	// Add test environment variable
	envVars = append(envVars, corev1.EnvVar{
		Name:  "TEST_HOOK",
		Value: "asdfsd",
	})

	klog.Infof("Total environment variables to inject: %d", len(envVars))
	for i, env := range envVars {
		klog.Infof("EnvVar %d: %s=%s", i, env.Name, env.Value)
	}

	// Add environment variables patch
	if len(envVars) > 0 {
		patches = append(patches, ws.createEnvVarPatches(envVars, &deployment, deploymentType)...)
	}

	// Set replicas from environment variable or default to 1
	replicas := ws.getDesiredReplicas()
	if deployment.Spec.Replicas == nil || *deployment.Spec.Replicas != replicas {
		patches = append(patches, patchOperation{
			Op:    "replace",
			Path:  "/spec/replicas",
			Value: replicas,
		})
	}

	klog.Infof("Generated %d total patches for deployment %s", len(patches), deployment.Name)
	for i, patch := range patches {
		klog.Infof("Patch %d: op=%s path=%s value=%v", i, patch.Op, patch.Path, patch.Value)
	}
	
	patchBytes, _ := json.Marshal(patches)
	klog.Infof("Final patch JSON (%d bytes): %s", len(patchBytes), string(patchBytes))

	return &admissionv1.AdmissionResponse{
		UID:     req.UID,
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *admissionv1.PatchType {
			pt := admissionv1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

func (ws *WebhookServer) getDeploymentType(deployment *appsv1.Deployment) string {
	// Check if this deployment has specific containers
	for _, container := range deployment.Spec.Template.Spec.Containers {
		if container.Name == "argus" {
			return "argus"
		}
		if container.Name == "collectorset-controller" {
			return "collectorset"
		}
	}
	return "unknown"
}

func (ws *WebhookServer) getArgusEnvironmentVariables(namespace string) ([]corev1.EnvVar, error) {
	var envVars []corev1.EnvVar

	// Get user-defined secret name from environment variable
	userDefinedSecret := os.Getenv("USER_DEFINED_SECRET")
	if userDefinedSecret == "" {
		klog.Info("No user-defined secret specified")
		return ws.getDefaultEnvironmentVariables(), nil
	}

	// Get the secret
	secret, err := ws.k8sClient.CoreV1().Secrets(namespace).Get(context.TODO(), userDefinedSecret, metav1.GetOptions{})
	if err != nil {
		klog.Errorf("Failed to get secret %s: %v", userDefinedSecret, err)
		return ws.getDefaultEnvironmentVariables(), nil
	}

	// Check for company domain in secret
	if companyDomainBytes, exists := secret.Data["companyDomain"]; exists {
		envVars = append(envVars, corev1.EnvVar{
			Name: "COMPANY_DOMAIN",
			ValueFrom: &corev1.EnvVarSource{
				SecretKeyRef: &corev1.SecretKeySelector{
					LocalObjectReference: corev1.LocalObjectReference{
						Name: userDefinedSecret,
					},
					Key: "companyDomain",
				},
			},
		})
		klog.Infof("Using company domain from secret: %s", string(companyDomainBytes))
	} else {
		// Use default company domain from environment variable
		defaultDomain := os.Getenv("COMPANY_DOMAIN")
		if defaultDomain == "" {
			defaultDomain = "logicmonitor.com"
		}
		envVars = append(envVars, corev1.EnvVar{
			Name:  "COMPANY_DOMAIN",
			Value: defaultDomain,
		})
	}

	// Check for etcdDiscoveryToken
	if _, exists := secret.Data["etcdDiscoveryToken"]; exists {
		envVars = append(envVars, corev1.EnvVar{
			Name: "ETCD_DISCOVERY_TOKEN",
			ValueFrom: &corev1.EnvVarSource{
				SecretKeyRef: &corev1.SecretKeySelector{
					LocalObjectReference: corev1.LocalObjectReference{
						Name: ws.getSecretName(namespace),
					},
					Key: "etcdDiscoveryToken",
				},
			},
		})
	}

	// Check for proxy settings
	proxyUserKeys := []string{"argusProxyUser", "proxyUser"}
	for _, key := range proxyUserKeys {
		if _, exists := secret.Data[key]; exists {
			envVars = append(envVars, corev1.EnvVar{
				Name: "PROXY_USER",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: ws.getSecretName(namespace),
						},
						Key: key,
					},
				},
			})
			break
		}
	}

	proxyPassKeys := []string{"argusProxyPass", "proxyPass"}
	for _, key := range proxyPassKeys {
		if _, exists := secret.Data[key]; exists {
			envVars = append(envVars, corev1.EnvVar{
				Name: "PROXY_PASS",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: ws.getSecretName(namespace),
						},
						Key: key,
					},
				},
			})
			break
		}
	}

	return envVars, nil
}

func (ws *WebhookServer) getDefaultEnvironmentVariables() []corev1.EnvVar {
	defaultDomain := os.Getenv("COMPANY_DOMAIN")
	if defaultDomain == "" {
		defaultDomain = "logicmonitor.com"
	}

	return []corev1.EnvVar{
		{
			Name:  "COMPANY_DOMAIN",
			Value: defaultDomain,
		},
	}
}

func (ws *WebhookServer) getSecretName(namespace string) string {
	// This should match the lmutil.secret-name template
	releaseName := os.Getenv("RELEASE_NAME")
	if releaseName == "" {
		return "argus-secret"
	}
	return fmt.Sprintf("%s-secret", releaseName)
}

func (ws *WebhookServer) getDesiredReplicas() int32 {
	replicasStr := os.Getenv("DESIRED_REPLICAS")
	if replicasStr == "" {
		return 1
	}

	replicas, err := strconv.Atoi(replicasStr)
	if err != nil {
		klog.Errorf("Invalid DESIRED_REPLICAS value: %s", replicasStr)
		return 1
	}

	return int32(replicas)
}

func (ws *WebhookServer) createEnvVarPatches(envVars []corev1.EnvVar, deployment *appsv1.Deployment, deploymentType string) []patchOperation {
	var patches []patchOperation

	// Find the target container based on deployment type
	var targetContainerName string
	switch deploymentType {
	case "argus":
		targetContainerName = "argus"
	case "collectorset":
		targetContainerName = "collectorset-controller"
	default:
		klog.Errorf("Unknown deployment type: %s", deploymentType)
		return patches
	}
	
	targetContainerIndex := -1
	for i, container := range deployment.Spec.Template.Spec.Containers {
		if container.Name == targetContainerName {
			targetContainerIndex = i
			break
		}
	}

	if targetContainerIndex == -1 {
		klog.Errorf("%s container not found in deployment", targetContainerName)
		return patches
	}

	klog.Infof("Found %s container at index %d", targetContainerName, targetContainerIndex)
	container := &deployment.Spec.Template.Spec.Containers[targetContainerIndex]
	
	// Check if the container has an env field
	if container.Env == nil {
		klog.Info("Container has no existing env field, creating it first")
		// Create the env array first
		patches = append(patches, patchOperation{
			Op:    "add",
			Path:  fmt.Sprintf("/spec/template/spec/containers/%d/env", targetContainerIndex),
			Value: []corev1.EnvVar{},
		})
	} else {
		klog.Infof("Container already has %d environment variables", len(container.Env))
	}

	// Add each environment variable
	for _, envVar := range envVars {
		// Check if the environment variable already exists
		exists := false
		for _, existingEnv := range deployment.Spec.Template.Spec.Containers[targetContainerIndex].Env {
			if existingEnv.Name == envVar.Name {
				exists = true
				break
			}
		}

		if !exists {
			klog.Infof("Adding environment variable: %s=%s", envVar.Name, envVar.Value)
			patches = append(patches, patchOperation{
				Op:    "add",
				Path:  fmt.Sprintf("/spec/template/spec/containers/%d/env/-", targetContainerIndex),
				Value: envVar,
			})
		} else {
			klog.Infof("Environment variable %s already exists, skipping", envVar.Name)
		}
	}

	return patches
}

func (ws *WebhookServer) getCollectorsetEnvironmentVariables(namespace, deploymentName string) ([]corev1.EnvVar, error) {
	var envVars []corev1.EnvVar

	// Get user-defined secret name from environment variable
	userDefinedSecret := os.Getenv("USER_DEFINED_SECRET")
	
	// Implement lmutil.secret-name logic: if userDefinedSecret is set, use it; otherwise use deployment name
	secretName := userDefinedSecret
	if secretName == "" {
		secretName = deploymentName // This replaces the lmutil.fullname logic
	}
	
	klog.Infof("Using secret name for collectorset: %s", secretName)

	if userDefinedSecret != "" {
		klog.Infof("Looking up secret %s for collectorset environment variables", userDefinedSecret)
		
		// Get the secret to determine what env vars to create
		secret, err := ws.k8sClient.CoreV1().Secrets(namespace).Get(context.TODO(), userDefinedSecret, metav1.GetOptions{})
		if err != nil {
			klog.Errorf("Failed to get secret %s: %v", userDefinedSecret, err)
			return envVars, nil // Continue without error as secret might not exist yet
		}

		// Check for company domain in secret
		if _, hasCompanyDomain := secret.Data["companyDomain"]; hasCompanyDomain {
			klog.Info("Secret contains companyDomain key, using secretKeyRef")
			envVars = append(envVars, corev1.EnvVar{
				Name: "COMPANY_DOMAIN",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: userDefinedSecret,
						},
						Key: "companyDomain",
					},
				},
			})
		} else {
			klog.Info("Secret does not contain companyDomain key, using default value")
			companyDomain := os.Getenv("COMPANY_DOMAIN")
			if companyDomain == "" {
				companyDomain = "logicmonitor.com"
			}
			envVars = append(envVars, corev1.EnvVar{
				Name:  "COMPANY_DOMAIN",
				Value: companyDomain,
			})
		}

		// Add other environment variables based on secret content
		if _, hasEtcdToken := secret.Data["etcdDiscoveryToken"]; hasEtcdToken {
			klog.Info("etcdDiscoveryToken found in secret, adding to env")
			envVars = append(envVars, corev1.EnvVar{
				Name: "ETCD_DISCOVERY_TOKEN",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: secretName,
						},
						Key: "etcdDiscoveryToken",
					},
				},
			})
		}

		// Check for proxy user variations
		if _, hasArgusProxyUser := secret.Data["argusProxyUser"]; hasArgusProxyUser {
			klog.Info("Argus proxyUser found in secret, adding to env")
			envVars = append(envVars, corev1.EnvVar{
				Name: "PROXY_USER",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: secretName,
						},
						Key: "argusProxyUser",
					},
				},
			})
		} else if _, hasProxyUser := secret.Data["proxyUser"]; hasProxyUser {
			klog.Info("ProxyUser found in secret, adding to env")
			envVars = append(envVars, corev1.EnvVar{
				Name: "PROXY_USER",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: secretName,
						},
						Key: "proxyUser",
					},
				},
			})
		}

		// Check for proxy pass variations
		if _, hasArgusProxyPass := secret.Data["argusProxyPass"]; hasArgusProxyPass {
			klog.Info("Argus proxyPass found in secret, adding to env")
			envVars = append(envVars, corev1.EnvVar{
				Name: "PROXY_PASS",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: secretName,
						},
						Key: "argusProxyPass",
					},
				},
			})
		} else if _, hasProxyPass := secret.Data["proxyPass"]; hasProxyPass {
			klog.Info("ProxyPass found in secret, adding to env")
			envVars = append(envVars, corev1.EnvVar{
				Name: "PROXY_PASS",
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: secretName,
						},
						Key: "proxyPass",
					},
				},
			})
		}
	} else {
		klog.Info("No userDefinedSecret specified, using default company domain")
		companyDomain := os.Getenv("COMPANY_DOMAIN")
		if companyDomain == "" {
			companyDomain = "logicmonitor.com"
		}
		envVars = append(envVars, corev1.EnvVar{
			Name:  "COMPANY_DOMAIN",
			Value: companyDomain,
		})
	}

	return envVars, nil
}
