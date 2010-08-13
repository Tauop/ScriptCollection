#!/bin/bash

. ../lib/functions.lib.sh
SOURCE ../lib/mysql.lib.sh
SOURCE ../lib/ask.lib.sh

from_host=
from_db=
from_user=
form_pass=

to_host=
to_db=
to_user=
to_pass=

SET_LOG_FILE "/tmp/check_db_structure"

MESSAGE --no-log "Ce script a pour objectif de comparer les structures de deux bases de données MySQL."
MESSAGE --no-log "Nous comparons une base A avec une base B, en vous indiquant les différences."

# ------------------------------------------------------------------------------------------------------
MESSAGE "Récolte d'information sur la base A"
ASK from_host        "IP du serveur ? "
ASK from_user        "nom d'utilisateur ? "
ASK --pass from_pass "mot de passe ? "
ASK from_db          "nom de la base ? "

MESSAGE "Récolte d'information sur la base B"
ASK to_host        "IP du serveur [${from_host}] ? "     "${from_host}"
ASK to_user        "nom d'utilisateur [${from_user}] ? " "${from_user}"
ASK --pass to_pass "mot de passe ? "
ASK to_db          "nom de la base [${from_db}] ? "      "${from_db}"

from_opt="--host ${from_host} --db ${from_db} --user ${from_user} --pass ${from_pass}"
to_opt="--host ${to_host} --db ${to_db} --user ${to_user} --pass ${to_pass}"


MYSQL_QUERY ${from_opt} --bash "SELECT 1" >/dev/null 2>/dev/null
[ $? -ne 0 ] && FATAL "Unable to connect to base A"

MYSQL_QUERY ${to_opt} --bash "SELECT 1" >/dev/null 2>/dev/null
[ $? -ne 0 ] && FATAL "Unable to connect to base B"

# ------------------------------------------------------------------------------------------------------

FROM_TMP_FILE="/tmp/check.${RANDOM}"
TO_TMP_FILE="/tmp/check.${RANDOM}"

ROLLBACK() {
  rm -f ${FROM_TMP_FILE}
  rm -f ${TO_TMP_FILE}
}

# ------------------------------------------------------------------------------------------------------
echo ". Verification de la liste des tables"

from_table_list=$( MYSQL_GET_TABLES ${from_opt} )
to_table_list=$( MYSQL_GET_TABLES ${to_opt} )

echo "${from_table_list}" | sort -u > ${FROM_TMP_FILE}
echo "${to_table_list}" | sort -u > ${TO_TMP_FILE}

added_tables=$(   diff -u ${FROM_TMP_FILE} ${TO_TMP_FILE} | grep '^+' | grep -v -- '+++' | sed -e 's/^+//' | tr $'\n' ' ' )
deleted_tables=$( diff -u ${FROM_TMP_FILE} ${TO_TMP_FILE} | grep '^-' | grep -v -- '---' | sed -e 's/^-//' | tr $'\n' ' ' )
added_tables=${added_tables%% }
deleted_tables=${deleted_tables%% }

if [ -n "${added_tables}" ]; then
  echo "  [Erreur] Tables presentes dans ${to_db} mais pas dans ${from_db} : ${added_tables// /,}"
fi
if [ -n "${deleted_tables}" ]; then
  echo "  [Erreur] Tables presentes dans ${from_db} mais pas dans ${to_db} : ${deleted_tables// /,}"
fi

# ------------------------------------------------------------------------------------------------------
echo ". Verification des tables"

common_table_list=$( (echo "${from_table_list}"; echo "${to_table_list}" ) | sort -u | tr $'\n' ' ')
common_table_list=" ${common_table_list} "
for table in ${added_tables}; do
  common_table_list=${common_table_list/ ${table} / }
done
for table in ${deleted_tables}; do
  common_table_list=${common_table_list/ ${table} / }
done

for table in ${common_table_list}; do
  from_fields=$( MYSQL_GET_FIELDS ${from_opt} ${table} | sort -u )
  to_fields=$( MYSQL_GET_FIELDS ${to_opt} ${table} | sort -u )
  common_fields=$( (echo "${from_fields}"; echo "${to_fields}" ) | sort -u | tr $'\n' ' ')
  common_fields=" $common_fields "

  # check field presence
  if [ "${from_fields}" != "${to_fields}" ]; then
    echo "${from_fields}" > ${FROM_TMP_FILE}
    echo "${to_fields}" > ${TO_TMP_FILE}
    added_fields=$(   diff -u ${FROM_TMP_FILE} ${TO_TMP_FILE} | grep '^+' | grep -v -- '+++' | sed -e 's/^+//' | tr $'\n' ' ')
    deleted_fields=$( diff -u ${FROM_TMP_FILE} ${TO_TMP_FILE} | grep '^-' | grep -v -- '---' | sed -e 's/^-//' | tr $'\n' ' ' )
    added_fields=${added_fields%% }
    deleted_fields=${deleted_fields%% }

    if [ -n "${added_fields}" ]; then
      echo "  [Erreur] Champs \"${added_fields// /,}\" presents dans ${to_db}.${table} mais pas dans ${from_db}.${table}"
    fi
    if [ -n "${deleted_fields}"  ]; then
      echo "  [Erreur] Champs \"${deleted_fields// /,}\" presents dans ${from_db}.${table} mais pas dans ${to_db}.${table}"
    fi
    for field in ${added_fields}; do
      common_fields=${common_fields/ ${field} / }
    done
    for field in ${deleted_fields}; do
      common_fields=${common_fields/ ${field} / }
    done
  fi

  # check type of each field :-)
  for field in $common_fields; do
    from_field_type=$( MYSQL_GET_FIELD_TYPE ${from_opt} ${table} ${field} )
    to_field_type=$(   MYSQL_GET_FIELD_TYPE ${to_opt} ${table} ${field} )

    from_field_simple_type=$( echo "${from_field_type}" | sed -e 's/[(].*[)]$//' )
    to_field_simple_type=$(   echo "${to_field_type}" | sed -e 's/[(].*[)]$//' )

    if [ "${from_field_simple_type}" != "${to_field_simple_type}" ]; then
        echo "  [Erreur - pb de typage] ${table}.${field} --> (${from_db}) ${from_field_simple_type} != ${to_field_simple_type} (${to_db})"
    else
      if [ "${from_field_type}" != "${to_field_type}" ]; then
        echo "  [Warning]  pb de taille : ${table}.${field} => (${from_db}) ${from_field_type} != ${to_field_type} (${to_db})"
      fi
    fi
  done
done

ROLLBACK