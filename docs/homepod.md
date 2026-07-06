# HomePod / Bonjour Audio

HomePod discovery is not automated by chezmoi in this repo. It depends on
system packages, system service state, and `/etc` configuration that should be
reviewed per machine.

## Packages

On Arch-based systems, install the relevant packages outside chezmoi:

```bash
sudo pacman -S --needed avahi nss-mdns pipewire-zeroconf
```

Other distributions use different package names, but the required pieces are:

- Avahi for mDNS service discovery.
- NSS mDNS integration, commonly `nss-mdns`.
- PipeWire RAOP support, commonly `pipewire-zeroconf`.

## Name Resolution

Check `/etc/nsswitch.conf` and make sure the `hosts:` line includes mDNS before
plain DNS lookup. One working shape is:

```text
hosts: mymachines resolve [!UNAVAIL=return] files myhostname mdns_minimal [NOTFOUND=return] dns
```

Keep any local distribution-specific entries that are already required on the
machine.

## Services

Enable Avahi system-wide:

```bash
sudo systemctl enable --now avahi-daemon.service
```

Restart PipeWire after changing RAOP or zeroconf configuration:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

## PipeWire RAOP

This repo does not currently manage the RAOP config as a home file. If a machine
needs it, keep this local file:

```text
~/.config/pipewire/pipewire.conf.d/50-raop.conf
```

With:

```ini
context.modules = [
    # Discover AirPlay/RAOP speakers advertised through mDNS.
    { name = libpipewire-module-raop-discover
        condition = [ { module.raop = !false } ]
    }
]
```
