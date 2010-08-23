#!/bin/bash
#
# Copyright (c) 2006-2010 Linagora
# http://github.com/Tauop/ScriptCollection
#
# ScriptCollection is free software, you can redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# ScriptCollection is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# README ---------------------------------------------------------------------
# this script is used to compare two database structure. For example, it can
# be used to compare pre-production and production database for modifications.
#
# Usage: ./compare_db_structure.sh
# Author: Patrick Guiran <pguiran@linagora.com>
#
# Note : Depends on ScriptHelper (http://github.com/Tauop/ScriptHelper), which
#        has to be present in ../lib directory

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

table_prefix=

SET_LOG_FILE "/tmp/check_db_structure"

# ------------------------------------------------------------------------------------------------------
MESSAGE "First database information"
ASK from_host        "MySQL host ? "
ASK from_user        "User login ? "
ASK --pass from_pass "User password ? "
ASK from_db          "Database name ? "
BR

MESSAGE "Second database information"
ASK to_host        "MySQL host [${from_host}] ? "     "${from_host}"
ASK to_user        "User login [${from_user}] ? " "${from_user}"
ASK --pass to_pass "User password ? "
ASK to_db          "Database name [${from_db}] ? "      "${from_db}"
BR

ASK --allow-empty table_prefix "Prefix of the table to compare (empty = compare all tables) ? "
BR

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
MESSAGE ". Check tables list"

from_table_list=$( MYSQL_GET_TABLES ${from_opt} )
to_table_list=$( MYSQL_GET_TABLES ${to_opt} )

if [ -n "${table_prefix}" ]; then
  from_table_list=$( echo "${from_table_list}" | grep "^${table_prefix}" )
  to_table_list=$(   echo "${to_table_list}"   | grep "^${table_prefix}" )
fi

echo "${from_table_list}" | sort -u > ${FROM_TMP_FILE}
echo "${to_table_list}"   | sort -u > ${TO_TMP_FILE}

added_tables=$(   diff -u ${FROM_TMP_FILE} ${TO_TMP_FILE} | grep '^+' | grep -v -- '+++' | sed -e 's/^+//' | tr $'\n' ' ' )
deleted_tables=$( diff -u ${FROM_TMP_FILE} ${TO_TMP_FILE} | grep '^-' | grep -v -- '---' | sed -e 's/^-//' | tr $'\n' ' ' )
added_tables=${added_tables%% }
deleted_tables=${deleted_tables%% }

if [ -n "${added_tables}" ]; then
  ERROR "[Table mismatch] Tables '${added_tables// /,}' exist(s) in database ${to_db} but not in database ${from_db}"
fi
if [ -n "${deleted_tables}" ]; then
  ERROR "[Table mismatch] Tables '${deleted_tables// /,}' exist(s) in database ${from_db} but not in database ${to_db}"
fi

# ------------------------------------------------------------------------------------------------------
MESSAGE ". Check tables structure"

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
      ERROR "[Field missing] Field \"${added_fields// /,}\" in table ${to_db}.${table} not present in table ${from_db}.${table}"
    fi
    if [ -n "${deleted_fields}"  ]; then
      ERROR "[Field missing] Field \"${deleted_fields// /,}\" in table ${from_db}.${table} not present in table ${to_db}.${table}"
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
        ERROR "[Field type mismatch] ${table}.${field} --> (${from_db}) ${from_field_simple_type} != ${to_field_simple_type} (${to_db})"
    else
      if [ "${from_field_type}" != "${to_field_type}" ]; then
        WARNING "[Field size mismatch] ${table}.${field} => (${from_db}) ${from_field_type} != ${to_field_type} (${to_db})"
      fi
    fi
  done
done

ROLLBACK

MESSAGE "All check finished !"
