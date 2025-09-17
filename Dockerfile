FROM amazonlinux:2
ENV SONATYPE_DIR=/opt/sonatype
ENV NEXUS_HOME=${SONATYPE_DIR}/nexus \
    NEXUS_DATA=${SONATYPE_DIR}/nexus3 \
    NEXUS_CONTEXT='' \
    SONATYPE_WORK=${SONATYPE_DIR}/sonatype-work \
    NEXUS_USER=nexus \
    NEXUS_GROUP=nexus \
    NEXUS_UID=200 \
    NEXUS_GID=200 \
    JAVA_HOME=/opt/sonatype/jdk-17.0.12 \
    DOCKER_TYPE='rh-docker'

RUN yum update -y \
    && yum install -y \
    procps \
    curl \
    wget \
    jq \
    tar \
    xz \
    tail

RUN groupadd -g 200 -r nexus \
    && useradd -u 200 -r nexus -g nexus -s /bin/false -d /opt/sonatype/nexus -c 'Nexus Repository Manager user'

WORKDIR /opt/sonatype
RUN wget https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.tar.gz
COPY nexus-3.76.0-03-unix.tar.gz ${SONATYPE_DIR}/
RUN tar -xzvf nexus-3.76.0-03-unix.tar.gz \
    && tar -xzvf jdk-17.0.12_linux-x64_bin.tar.gz \
    && rm -f nexus-3.76.0-03-unix.tar.gz* jdk-17.0.12_linux-x64_bin.tar.gz* \
    && mkdir ${SONATYPE_DIR}/nexus3 \
    && mv nexus-3.76.0-03 $NEXUS_HOME \
    && chown -R nexus:nexus ${SONATYPE_DIR} \
    && ln -s ${NEXUS_DATA} ${SONATYPE_WORK}/nexus3


RUN sed -i '/^-Xms/d;/^-Xmx/d;/^-XX:MaxDirectMemorySize/d' $NEXUS_HOME/bin/nexus.vmoptions

RUN echo "#!/bin/bash" >> ${SONATYPE_DIR}/start-nexus-repository-manager.sh \
    && echo "cd /opt/sonatype/nexus" >> ${SONATYPE_DIR}/start-nexus-repository-manager.sh \
    && echo "exec ./bin/nexus run" >> ${SONATYPE_DIR}/start-nexus-repository-manager.sh \
    && chmod a+x ${SONATYPE_DIR}/start-nexus-repository-manager.sh \
    && sed -e '/^nexus-context/ s:$:${NEXUS_CONTEXT}:' -i ${NEXUS_HOME}/etc/nexus-default.properties

VOLUME ${NEXUS_DATA}

EXPOSE 8081
USER nexus

ENV INSTALL4J_ADD_VM_PARAMS="-Xms1256m -Xmx1256m -XX:MaxDirectMemorySize=1256m -Djava.util.prefs.userRoot=${NEXUS_DATA}/javaprefs"

CMD ["/opt/sonatype/nexus/bin/nexus", "run"]




# chown -R 200:200 /mnt/efs/opt/nexus/data
# sudo chmod -R 770 /mnt/efs/opt/nexus/data
# sudo chown -R 200:200 /mnt/efs/opt/nexus/logs
# sudo chmod -R 770 /mnt/efs/opt/nexus/logs