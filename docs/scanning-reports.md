# HOWTO review scanning reports

Before you do anything else, set `KUBECONFIG` to the location of your kubeconfig file for accessing your cluster.
## Using the Starboard CLI

1. [Install the Starboard CLI](https://aquasecurity.github.io/starboard/v0.15.2/cli/) and learn to use it

## Using the Octant k8s client UI

1. Install Octant

    ```bash
    brew install octant
    ```

2. Install the Starboard plugin for Octant in the plugins directory

    ```bash
    mkdir -p $HOME/.config/octant/plugins
    cd !$
    curl -L https://github.com/aquasecurity/starboard-octant-plugin/releases/download/v0.12.0/starboard-octant-plugin_linux_x86_64.tar.gz | tar xzvf -
    rm README.md LICENSE
    cd -
    ```

3. Run Octant (in the background)

    ```bash
    octant &
    ```

4. Open the Octant UI in your browser

    ```bash
    open http://127.0.0.1:7777
    ```

5. Click around. Just about every resource will have a scan results tab of some sort.
