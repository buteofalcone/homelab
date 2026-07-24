# Watchtower

Watchtower runs in label-enable mode. It updates only containers carrying:

```yaml
com.centurylinklabs.watchtower.enable: "true"
```

Only low-risk stateless management containers are opted in. Stateful services remain manual.
