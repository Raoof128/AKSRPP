# Multi-stage build for Go operator
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum* ./
RUN go mod download

# Copy source
COPY *.go ./

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o security-operator .

# Final stage
FROM alpine:3.18

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy binary
COPY --from=builder /app/security-operator .

# Create forensics directory
RUN mkdir -p /forensics

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

CMD ["./security-operator"]
