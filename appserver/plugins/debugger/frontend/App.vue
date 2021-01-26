<template>
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>RoadRunner Debugger</title>
    </head>
    <body>
        <h1>RR gRPC Debugger</h1>
        <div v-for="(log, id) in debuglogs" :key=id>
            <Dump :value=log></Dump>
        </div>
    </body>
    </html>
</template>

<script>
import Dump from './Dump.vue';

export default {
    data() {
        return {
            "debuglogs": [],
        }
    },
	components: {
		Dump
    },
    created() {
        this.fetch()
    },
    methods: {
        fetch() {
            fetch("http://localhost:8089/debuglogs").then((v) => v.json().then((d) => this.debuglogs = d))
        },
    }
}
</script>
