ARG QUICKSTART_IMAGE_REF=stellar/quickstart:soroban-dev
ARG SOROBAN_CLI_IMAGE_REF=stellar/system-test-soroban-cli:dev

FROM golang:1.19 as go

RUN ["mkdir", "-p", "/test"] 
RUN ["mkdir", "-p", "/test/bin"] 

WORKDIR /test
ADD go.mod go.sum ./
RUN go mod download
ADD e2e.go ./
ADD features ./features

# build each feature folder with go test module.
# compiles each feature to a binary to be executed, 
# and copies the .feature file with it for runtime.
RUN go test -c -o ./bin/dapp_develop_test.bin ./features/dapp_develop/...
ADD features/dapp_develop/dapp_develop.feature ./bin
# copy over a dapp develop test specific file, used for expect/tty usage
ADD features/dapp_develop/soroban_config.exp ./bin

FROM $SOROBAN_CLI_IMAGE_REF as soroban-cli

FROM $QUICKSTART_IMAGE_REF as base
ARG RUST_TOOLCHAIN_VERSION
ARG NODE_VERSION

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y build-essential expect && apt-get clean

# Install Rust
RUN ["mkdir", "-p", "/rust"] 
ENV CARGO_HOME=/rust/.cargo
ENV RUSTUP_HOME=/rust/.rust
ENV RUST_TOOLCHAIN_VERSION=$RUST_TOOLCHAIN_VERSION
ENV PATH="/usr/local/go/bin:$CARGO_HOME/bin:${PATH}"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain "$RUST_TOOLCHAIN_VERSION"

# Install Node.js
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
ENV NVM_DIR=/root/.nvm
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"

# Install phantomjs
RUN apt -y install phantomjs
ENV QT_QPA_PLATFORM=offscreen
RUN npm i -g ts-node

# Create our workdir
RUN ["mkdir", "-p", "/opt/test"]
WORKDIR /opt/test

# Install js-soroban-client
ARG JS_SOROBAN_CLIENT_NPM_VERSION
ADD package*.json /opt/test/
RUN npm install "soroban-client@${JS_SOROBAN_CLIENT_NPM_VERSION}" && npm ci --only=production
ADD invoke.ts /opt/test/

FROM base as build
ADD start /opt/test
COPY --from=soroban-cli /usr/local/cargo/bin/soroban $CARGO_HOME/bin/
COPY --from=go /test/bin/ /opt/test/bin

RUN ["chmod", "+x", "/opt/test/start"]

ENTRYPOINT ["/opt/test/start"]
